sink("parallelGLMTuning.txt")

library("doParallel")
library("data.table")

Sys.info()
sessionInfo()

# Set up the test data
J <- 100  # This is the number of models to fit
N <- 2.5e5  # This is the size of the dataset
i <- rep(1:N, each=J)
D <- data.table(i,  # id
                j = rep(1:J, N),  # index repitition
                x1 = rep(rbinom(N, 1, 0.5), each=J),  # group membership, adult/child
                x2 = rnorm(N * J),  # fake risk factor
                x3 = rnorm(N * J),  # fake risk factor
                x4 = rbinom(N * J, 1, 0.5),  # fake risk factor
                x5 = rbinom(N * J, 1, 0.5))  # fake risk factor
D <- D[, logitp := -5 + x1 + x2 + x3 + x4 + x5]
D <- D[, p := exp(logitp) / (1 + exp(logitp))]
D <- D[, y := rbinom(N * J, 1, p)]
D <- rbind(D[, k := j], 
           D[x1 == 0, ][, k := as.integer(J * (x1 + 1) + j)], 
           D[x1 == 1, ][, k := as.integer(J * (x1 + 1) + j)])
setkey(D, k, i, j)
rm(i)
message(sprintf("Size of data.table() object: %.05g GB", object.size(D) / 1e9))

# Define the wrapper functions
runClusters <- function (workers, D) {
  model <- function (D) {
    require(data.table)
    fx <- formula(y ~ x1 + x2 + x3 + x4 + x5)
    M <- glm(fx, data=D, family=binomial)
    fitted(M)
  }
  summarize <- function (workers, t, p) {
    data.frame(workers=workers,
               user = t[1],
               sys = t[2],
               elapsed = t[3],
               meanPhat = mean(unlist(p)),
               row.names = NULL)
  }
  cl <- makeCluster(workers)
  registerDoParallel(cl, cores=workers)
  ptime <- system.time(
    phat <- foreach(K = 1:(J * 3)) %dopar% {
      model(D[k == K, ])
    }
  )
  stopCluster(cl)
  summarize(workers, ptime, phat)
}

# Run with various number of workers
n16 <- runClusters(16, D)
n12 <- runClusters(12, D)
n8  <- runClusters(8 , D)
n6  <- runClusters(6 , D)
n5  <- runClusters(5 , D)
n4  <- runClusters(4 , D)
n3  <- runClusters(3 , D)
n2  <- runClusters(2 , D)
n1  <- runClusters(1 , D)

# Summarize
summary <- data.table(models = J,
                      size = N,
                      rbind(n16, n12, n8, n6, n5, n4, n3, n2, n1),
                      timestamp = Sys.time(),
                      nodename = Sys.info()["nodename"],
                      machine = Sys.info()["machine"],
                      user = Sys.info()["user"],
                      R.version = sessionInfo()$R.version$version.string,
                      platform = sessionInfo()$platform,
                      running = sessionInfo()$running)
write.csv(summary, file="parallelGLMTuning.csv", row.names=FALSE)
file.info("parallelGLMTuning.csv")

library(ggplot2)
G <- ggplot(summary, aes(x=workers, y=elapsed / 60))
G <- G + geom_point(size=5)
G <- G + geom_line(alpha=1/2, size=2)
G <- G + scale_x_continuous("Number of workers", breaks=summary$workers)
G <- G + scale_y_continuous("Elapsed time (minutes)")
G <- G + theme_minimal()
ggsave("parallelGLMTuning.png", width=6, height=4, units="in")
file.info("parallelGLMTuning.png")


sink()
