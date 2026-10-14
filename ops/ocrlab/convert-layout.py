"""convert-layout.py — DocLayout-YOLO DocStructBench to the Core ML model the app runs (`LayoutModel`, BUGS.md C57).

    python convert-layout.py <weights.pt> <out.mlpackage>
    xcrun coremlcompiler compile <out.mlpackage> <dir>     # -> <dir>/<out>.mlmodelc, renamed doclayout-yolo.mlmodelc

Weights: `juliozhao/DocLayout-YOLO-DocStructBench`, `doclayout_yolo_docstructbench_imgsz1024.pt` (AGPL-3.0), the
model the lab's ONNX build (`wybxc/DocLayout-YOLO-DocStructBench-onnx`) was exported from. Measured 2026-10-13 in a
venv of torch 2.7.0, torchvision 0.22.0, coremltools 9.0, doclayout-yolo, on 8 sample pages: every box over 0.25
and every label the ONNX build's, boxes within 0.00015 px and scores within 1e-5 of its top 300.

The output is the one-to-one head before selection, `[1, 14, anchors]`: left, top, right, bottom in grid cells, then
10 class scores; the app makes the anchors and the top-300 selection (`LayoutModel.decode`), because the head's own
gather takes float indices Core ML refuses. The input is ranged, 32-1,024 a side: the lab pads the short side only to
a multiple of 32, and an enumerated list of the 64 shapes traps in Core ML's CPU engine at prediction. Attention
reshapes from x itself, or the trace bakes in the traced shape. Core ML's GPU compiler rejects the graph (an MPSGraph
assertion), so the app runs it on the CPU, about 0.4-0.5 s a page here.
"""
import sys, torch, coremltools as ct
from doclayout_yolo import YOLOv10
from doclayout_yolo.nn.modules import block, head


def raw(self, x):
    y = self.forward_feat([xi.detach() for xi in x], self.one2one_cv2, self.one2one_cv3)
    box, cls = torch.cat([yi.flatten(2) for yi in y], 2).split((self.reg_max * 4, self.nc), 1)
    return torch.cat((self.dfl(box), cls.sigmoid()), 1)


def attention(self, x):
    q, k, v = self.qkv(x).flatten(2).unflatten(1, (self.num_heads, -1)).split(
        [self.key_dim, self.key_dim, self.head_dim], dim=2)
    attn = ((q.transpose(-2, -1) @ k) * self.scale).softmax(dim=-1)
    return self.proj((v @ attn.transpose(-2, -1)).flatten(1, 2).reshape_as(x) + self.pe(v.flatten(1, 2).reshape_as(x)))


head.v10Detect.forward = raw
block.Attention.forward = attention
net = YOLOv10(sys.argv[1]).model.float().eval()


class Wrap(torch.nn.Module):
    def __init__(self, n):
        super().__init__(); self.n = n

    def forward(self, x):
        y = self.n(x)
        return y[0] if isinstance(y, (tuple, list)) else y


traced = torch.jit.trace(Wrap(net).eval(), torch.rand(1, 3, 1024, 768), check_trace=False, strict=False)
side = lambda d: ct.RangeDim(32, 1024, default=d)
ml = ct.convert(traced, inputs=[ct.TensorType(name="images", shape=(1, 3, side(1024), side(768)))],
                outputs=[ct.TensorType(name="raw")], convert_to="mlprogram", compute_precision=ct.precision.FLOAT32,
                minimum_deployment_target=ct.target.macOS13, skip_model_load=True)
ml.short_description = ("DocLayout-YOLO DocStructBench (AGPL-3.0, juliozhao/DocLayout-YOLO-DocStructBench): one-to-one "
                        "head, [1, 14, anchors]: ltrb distances in grid cells, then 10 class scores")
ml.save(sys.argv[2])
