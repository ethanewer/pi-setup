The CIFAR-10 dataset is a standard image-classification benchmark. Write a Python script `/app/info.py` that writes `/app/cifar_info.json` describing CIFAR-10 from general knowledge (no network / dataset download is needed):

```json
{
  "classes": ["<each of the 10 official CIFAR-10 class labels, in the standard order>", ...],
  "num_classes": 10,
  "image_shape": [32, 32, 3],
  "num_train": 50000,
  "num_test": 10000
}
```

The `classes` array must contain the 10 exact class labels: `airplane`, `automobile`, `bird`, `cat`, `deer`, `dog`, `frog`, `horse`, `ship`, `truck` — in precisely the order written here. `image_shape` is the height, width, and color-channels of each image. `num_train` / `num_test` are the official training / test split sizes.

Then run your script so `/app/cifar_info.json` is produced.