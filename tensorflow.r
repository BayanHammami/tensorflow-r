#install.packages('tensorflow')
#install.packages('tfestimators')
#install.packages('keras')
#install.packages('tfdatasets')

library(ggplot2)
library(reshape2)
library(tensorflow)
library(tfestimators)
library(logging)

formatter.fewsdiagnostics <- function(record) {
  if(record$level <= loglevels[['INFO']])
    level <- 3
  else if(record$level <= loglevels[['WARNING']])
    level <- 2
  else if(record$level <= loglevels[['ERROR']])
    level <- 1
  else
    level <- 0
  
  sprintf('  <line level="%d" description="LizardScripter :: %s :: %s"/>\n', level, record$timestamp, record$msg)
}

addHandler(writeToFile, file="./testing.log", level='DEBUG', formatter = formatter.fewsdiagnostics )
loginfo('does it work?')

#packrat::set_opts(vcs.ignore.src = TRUE)
#packrat::set_opts(vcs.ignore.src = TRUE)

config <- config::get()
config::is_active("production")

data_dir <- "mnist-data"
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

sources <- list(
  
  train = list(
    x = "https://storage.googleapis.com/cvdf-datasets/mnist/train-images-idx3-ubyte.gz",
    y = "https://storage.googleapis.com/cvdf-datasets/mnist/train-labels-idx1-ubyte.gz"
  ),
  
  test = list(
    x = "https://storage.googleapis.com/cvdf-datasets/mnist/t10k-images-idx3-ubyte.gz",
    y = "https://storage.googleapis.com/cvdf-datasets/mnist/t10k-labels-idx1-ubyte.gz"
  )
  
)


read_idx <- function(file) {
  
  # create binary connection to file
  conn <- gzfile(file, open = "rb")
  on.exit(close(conn), add = TRUE)
  
  # read the magic number as sequence of 4 bytes
  magic <- readBin(conn, what = "raw", n = 4, endian = "big")
  ndims <- as.integer(magic[[4]])
  
  # read the dimensions (32-bit integers)
  dims <- readBin(conn, what = "integer", n = ndims, endian = "big")
  
  # read the rest in as a raw vector
  data <- readBin(conn, what = "raw", n = prod(dims), endian = "big")
  
  # convert to an integer vecto
  converted <- as.integer(data)
  
  # return plain vector for 1-dim array
  if (length(dims) == 1)
    return(converted)
  
  # wrap 3D data into matrix
  matrix(converted, nrow = dims[1], ncol = prod(dims[-1]), byrow = TRUE)
}

mnist <- rapply(sources, classes = "character", how = "list", function(url) {
  
  # download + extract the file at the URL
  target <- file.path(data_dir, basename(url))
  if (!file.exists(target))
    download.file(url, target)
  
  # read the IDX file
  read_idx(target)
  
})

mnist$train$x <- mnist$train$x / 255
mnist$test$x <- mnist$test$x / 255

n <- 36
indices <- sample(nrow(mnist$train$x), size = n)
data <- array(mnist$train$x[indices, ], dim = c(n, 28, 28))
melted <- melt(data, varnames = c("image", "x", "y"), value.name = "intensity")
ggplot(melted, aes(x = x, y = y, fill = intensity)) +
  geom_tile() +
  scale_fill_continuous(name = "Pixel Intensity") +
  scale_y_reverse() +
  facet_wrap(~ image, nrow = sqrt(n), ncol = sqrt(n)) +
  theme(
    strip.background = element_blank(),
    strip.text.x = element_blank(),
    panel.spacing = unit(0, "lines"),
    axis.text = element_blank(),
    axis.ticks = element_blank()
  ) +
  labs(
    title = "MNIST Image Data",
    subtitle = "Visualization of a sample of images contained in MNIST data set.",
    x = NULL,
    y = NULL
  )

classifier <- linear_classifier(
  feature_columns = feature_columns(
    column_numeric("x", shape = shape(784L))
  ),
  n_classes = 10L  # 10 digits
)

mnist_input_fn <- function(data, ...) {
  input_fn(
    data,
    response = "y",
    features = "x",
    batch_size = 128,
    ...
  )
}


# train the classifier
train(classifier, input_fn = mnist_input_fn(mnist$train), steps = 200)

# evaluate the classifier on the test dataset
evaluate(classifier, input_fn = mnist_input_fn(mnist$test), steps = 200)

# use our classifier to predict labels for a subset of the test dataset
predictions <- predict(classifier, input_fn = mnist_input_fn(mnist$test))

# plot predictions versus actual for small subset
n <- 20
indices <- sample(nrow(mnist$test$x), n)
classes <- vapply(indices, function(i) {
  predictions$classes[[i]]
}, character(1))

data <- array(mnist$test$x[indices, ], dim = c(n, 28, 28))
melted <- melt(data, varnames = c("image", "x", "y"), value.name = "intensity")
melted$class <- classes

image_labels <- setNames(
  sprintf("Predicted: %s\nActual: %s", classes, mnist$test$y[indices]),
  1:n
)

ggplot(melted, aes(x = x, y = y, fill = intensity)) +
  geom_tile() +
  scale_y_reverse() +
  facet_wrap(~ image, ncol = 5, labeller = labeller(image = image_labels)) +
  theme(
    panel.spacing = unit(0, "lines"),
    axis.text = element_blank(),
    axis.ticks = element_blank()
  ) +
  labs(
    title = "MNIST Image Data",
    subtitle = "Visualization of a sample of images contained in MNIST data set.",
    x = NULL,
    y = NULL
  )

