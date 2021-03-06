RemoveExtremes <- function(data) {
  for (i in 1:ncol(data)) {
    idx.max <- which(data[, i] == max(data[, i], na.rm = TRUE))
    if (length(idx.max) > 1) {
      data[idx.max, ] <- NA
    }
    idx.min <- which(data[, i] == min(data[, i], na.rm = TRUE))
    if (length(idx.min) > 1) {
      data[idx.min, ] <- NA
    }
  }    
  return(na.omit(data))
}

Rescale <- function(data) {
  return((data - mean(data)) / sd(data))
}

GetData <- function(path, name.1, name.2, name.3) {
  data.1 <- read.csv(
    file.path(path, name.1), 
    header = TRUE) %>% RemoveExtremes()
  data.2 <- read.csv(
    file.path(path, name.2), 
    header = TRUE) %>% RemoveExtremes()
  data.3 <- read.csv(
    file.path(path, name.3), 
    header = TRUE) %>% RemoveExtremes()
  
  data <- bind_rows(data.1, data.2, data.3) %>% 
    dplyr::mutate_each(funs(Rescale)) %>%
    dplyr::mutate(C = c(rep(1, nrow(data.1)), 
                        rep(2, nrow(data.2)), 
                        rep(3, nrow(data.3))))
  return(data)
}

SampleData <- function(data, n.obs, dims, seed) {
  set.seed(seed)
  data.1 <- data %>% SubSample(1, n.obs, dims)
  data.2 <- data %>% SubSample(2, n.obs, dims)
  data.3 <- data %>% SubSample(3, n.obs, dims)
  return(list(data.1 = data.1,
              data.2 = data.2,
              data.3 = data.3))
} 

SubSample <- function(data, class, n.obs, dims) {
  # Randomly select rows and deterministically select columns.
  data <- data %>% dplyr::filter(C == class) %>% dplyr::select(-C)
  return(data[sample(nrow(data), n.obs), dims])
}

RunCremid <- function(training, prior) {
  G <- length(training)
  n.obs <- nrow(training$data.1)
  idx <- sample(n.obs * G, n.obs * G)
  Y <- rbind(training$data.1, training$data.2, training$data.3)[idx, ]
  C <- c(rep(1, n.obs), rep(2, n.obs), rep(3, n.obs))[idx] 
    mcmc <- list(nburn = 5000, nsave = 500, nskip = 10, ndisplay = 100)
  return(Fit(Y, C, prior, mcmc))
}

RunMClust <- function(training) {
  fit.1 <- densityMclust(training$data.1)
  fit.2 <- densityMclust(training$data.2)
  fit.3 <- densityMclust(training$data.3)
  return(list(fit.1 = fit.1, fit.2 = fit.2, fit.3 = fit.3))
}

GetCremidScore <- function(testing, ans) {
  return(sum(LogScoreCremid(testing$data.1, 1, ans)) +
           sum(LogScoreCremid(testing$data.2, 2, ans)) +
           sum(LogScoreCremid(testing$data.3, 3, ans)))
}

GetMCScore <- function(testing, mc) {
  return(sum(LogScoreMC(testing$data.1, mc$fit.1)) +
           sum(LogScoreMC(testing$data.2, mc$fit.2)) +
           sum(LogScoreMC(testing$data.3, mc$fit.3)))
}

LogScoreMC <- function(x, mc) {
  output <- rep(0, nrow(x))     
  probs <- mc$parameters$pro
  mu <- mc$parameters$mean
  sigma <- mc$parameters$variance$sigma
  K <- ncol(mu)
  for (k in 1:K) {
    output <- output + probs[k] * dmvnorm(x, mu[, k], sigma[, , k])
  }
  return(log(output))
}

LogScoreCremid <- function(x, class, ans) {
  G <- dim(ans$chain$mu)[1]
  K <- ans$prior$K
  p <- ncol(ans$data$Y)
  niter <- ans$mcmc$nsave
  
  output <- rep(0, nrow(x))   
  Omega <- ans$chain$Omega
  mu <- ans$chain$mu  
  probs <- ans$chain$w
  
  for (it in 1:niter) {
    for (k in 1:K) {
      if (ans$chain$w[class, k, it] > 1 / 1E4) {
        ix <- seq(p * (k - 1) + 1, p * k)
        sigma <- chol2inv(chol(Omega[, ix, it]))
        m <- mu[class, ix, it]
        output <- output + 
          probs[class, k, it] * dmvnorm(x, m, sigma, log = FALSE)        
      }
    }
  }
  return(log(output / niter))
}

Histogram <- function(data, main = "", xlab = "", ...) {
  hist(data, prob = TRUE, col = "grey", 
       main = main, xlab = xlab, ...)
}

PlotHistograms <- function(ans, ...) {
  Histogram(ans$chain$rho, xlab = expression(rho), ...)
  x <- seq(0, 1, by = 0.00001)
  lines(x, 
        dbeta(x, ans$prior$tau_rho[1], ans$prior$tau_rho[2]), 
        col = "red", 
        lwd = 2)
  Histogram(ans$chain$varphi, xlab = expression(varphi), ...)
  lines(x, 
        dbeta(x, ans$prior$tau_varphi[1], ans$prior$tau_varphi[2]), 
        col = "red", 
        lwd = 2)
  Histogram(ans$chain$epsilon, xlab = expression(epsilon), ...)
  x <- seq(ans$prior$epsilon_range[1], ans$prior$epsilon_range[2], by = 0.0001)
  lx <- length(x)
  lines(x, 
        rep(1 / (ans$prior$epsilon_range[2] - ans$prior$epsilon_range[1]), lx), 
        col = "red", 
        lwd = 2)
}

ScatterPlotHyper <- function(ans) {
  plot(ans$chain$epsilon, 
       ans$chain$rho, 
       xlab = expression(epsilon), 
       ylab = expression(rho))
  plot(ans$chain$varphi, 
       ans$chain$rho,
       xlab = expression(varphi), 
       ylab = expression(rho))
  plot(ans$chain$varphi, 
       ans$chain$epsilon,
       xlab = expression(varphi), 
       ylab = expression(epsilon))
}


ExtractPosterior <- function(val, param, hyperparam) {
  return(data.frame(value = val) %>%
           dplyr::mutate(parameter = param,
                         hyperparameter = hyperparam))
}

DensityPlot <- function(data, title, xlab) {
  p <- data %>% 
    dplyr::mutate(hyperparameter = as.factor(hyperparameter)) %>%
    ggplot(aes(value, fill = hyperparameter, col= hyperparameter)) +
    geom_density(alpha = 0.1, adjust = 5) +
    scale_fill_discrete(name = title) +
    scale_color_discrete(name = title) +
    xlab(xlab)
  return(p)
}


Clusters <- function(ans) {
  n.save <- ans$mcmc$nsave
  n.clusters <- data.frame(shared = rep(0, n.save),
                           not.shared = rep(0, n.save))
  for (it in 1:n.save) {
    temp <- table(names(table(ans$chain$Z[it, ])) %in%
                    which(ans$chain$R[it, ] == 1))
    if ("FALSE" %in% names(temp)) {
      n.clusters$shared[it] <- temp[["FALSE"]]
    }
    if ("TRUE" %in% names(temp)) {
      n.clusters$not.shared[it] <- temp[["TRUE"]]
    }
  }
  return(n.clusters)
}
