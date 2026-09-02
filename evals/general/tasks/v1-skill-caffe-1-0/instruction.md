**Caffe 1.0** is a deep-learning framework (BVLC Caffe). Its network definitions are
protobuf text files (`.prototxt`) where layers are declared with `layer { ... }` blocks
(this is the modern Caffe 1.0 syntax; the pre-1.0 `layers { ... }` form is deprecated).
Caffe blobs have shape `N x C x H x W`. A typical Caffe workflow: define a network
(deploy.prototxt), subtract an image mean stored in a `mean.binaryproto` file, and train
with `caffe train --solver=solver.prototxt`.

In `/app/model` there is a Caffe 1.0 deploy prototxt `deploy.prototxt` for a small CNN
classifier. Read it and answer the following questions by writing
`/app/caffe_answers.json` (JSON object with exactly these keys):

```json
{
  "layer_count": <int, number of "layer { ... }" blocks in the file>,
  "input_blob_dims": [<N>, <C>, <H>, <W> from input_shape>,
  "conv1_kernel": <int, kernel_size of the "conv1" Convolution layer>,
  "num_classes": <int, num_output of the "fc8" InnerProduct layer>,
  "train_command": "<the caffe CLI command to train with a solver>",
  "mean_file": "<filename where Caffe stores the image mean>",
  "uses_legacy_layers_syntax": <true|false, whether the file uses the deprecated layers{} form>
}
```

The verifier parses `deploy.prototxt` itself for the file-derived values and checks the
two framework-knowledge answers (`train_command`, `mean_file`) against the standard Caffe
1.0 conventions described above.