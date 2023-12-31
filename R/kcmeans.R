#' K-Conditional-Means Estimator
#'
#' @description Implementation of the K-Conditional-Means estimator.
#'
#' @param y The outcome variable, a numerical vector.
#' @param X A (sparse) feature matrix where one column is the categorical
#'     predictor.
#' @param which_is_cat An integer indicating which column of \code{X}
#'     corresponds to the categorical predictor.
#' @param K The number of support points, an integer greater than 2.
#'
#' @return \code{kcmeans} returns an object of S3 class \code{kcmeans}. An
#'     object of class \code{kcmeans} is a list containing the following
#'     components:
#'     \describe{
#'         \item{\code{cluster_map}}{A matrix that characterizes the estimated
#'             predictor of the residualized outcome
#'             \eqn{\tilde{Y} \equiv Y - X_{2:}^\top \hat{\pi}}. The first column
#'             \code{x} denotes the value of the categorical variable that
#'             corresponds to the unrestricted sample mean \code{mean_x} of
#'             \eqn{\tilde{Y}}, the sample share \code{p_x}, the estimated
#'             cluster \code{cluster_x}, and the estimated restricted sample mean
#'             \code{mean_xK} of \eqn{\tilde{Y}} with just \code{K} support
#'             points.}
#'         \item{\code{mean_y}}{The unconditional sample mean of
#'             \eqn{\tilde{Y}}.}
#'         \item{\code{pi}}{The best linear prediction coefficients of \eqn{Y}
#'             on \eqn{X} corresponding to the non-categorical predictors
#'             \eqn{X_{2:}}.}
#'         \item{\code{which_is_cat},\code{K}}{Passthrough of
#'             user-provided arguments. See above for details.}
#'     }
#'
#' @references
#'
#' Wang H and Song M (2011). "Ckmeans.1d.dp: optimal k-means clustering in one
#'     dimension by dynamic programming." The R Journal 3(2), 29--33.
#'
#' Wiemann T (2023). "Optimal Categorical Instruments." <https://arxiv.org/abs/2311.17021>
#'
#' @export
#'
#' @examples
#' # Simulate simple dataset with n=800 observations
#' X <- rnorm(800) # continuous predictor
#' Z <- sample(1:20, 800, replace = TRUE) # categorical predictor
#' Z0 <- Z %% 4 # lower-dimensional latent categorical variable
#' y <- Z0 + X + rnorm(800) # outcome
#' # Compute kcmeans with four support points
#' kcmeans_fit <- kcmeans(y, cbind(Z, X), K = 4)
#' # Print the estimated support points of the categorical predictor
#' print(unique(kcmeans_fit$cluster_map[, "mean_xK"]))
kcmeans <- function(y, X, which_is_cat = 1, K = 2) {
  # Data parameters
  nobs <- length(y)
  # Check whether additional features are included, residualize accordingly
  if (length(X) > nobs) {
    Z <- X[, which_is_cat] # categorical variable
    X <- X[, -which_is_cat, drop = FALSE] # additional features
    # Compute \pi and residualize y
    nX <- ncol(X)
    Z_mat <- stats::model.matrix(~ 0 + as.factor(Z))
    ols_fit <- ols(y, cbind(X, Z_mat)) # ols w/ generalized inverse
    pi <- ols_fit$coef[1:nX]
    y <- y - X %*% pi
  } else {
    Z <- X # categorical variable
    pi <- NULL
  }#IFELSE
  # Prepare data and prepare the cluster map
  unique_Z <- unique(Z)
  cluster_map <- t(simplify2array(lapply(unique_Z, function (x) {
    c(x, mean(y[Z == x]), mean(Z == x))
    })))#LAPPLY
  # Estimate kmeans on means of D given Z = z
  kmeans_fit <- Ckmeans.1d.dp::Ckmeans.1d.dp(x = cluster_map[, 2], k = K,
                                             y = cluster_map[, 3])
  # Amend the cluster map
  cluster_map <- cbind(cluster_map, kmeans_fit$cluster,
                   kmeans_fit$centers[kmeans_fit$cluster])
  colnames(cluster_map) <- c("x", "mean_x", "p_x", "cluster_x", "mean_xK")
  # Compute the unconditional mean
  mean_y <- mean(y)
  # Prepare and return the model fit object
  X = cbind(X[, 1:which_is_cat])
  mdl_fit <- list(cluster_map = cluster_map,
                  mean_y = mean_y, pi = pi,
                  which_is_cat = which_is_cat,
                  K = K)
  class(mdl_fit) <- "kcmeans" # define S3 class
  return(mdl_fit)
}#kcmeans

#' Prediction Method for the K-Conditional-Means Estimator.
#'
#' @description Prediction method for the K-Conditional-Means estimator.
#'
#' @param object An object of class \code{kcmeans}.
#' @param newdata A (sparse) feature matrix where the first column corresponds
#'     to the categorical predictor.
#' @param clusters A boolean indicating whether estimated clusters should be
#'     returned.
#' @param ... Currently unused.
#'
#' @return A numerical vector with predicted values (if \code{clusters = FALSE})
#'     or predicted clusters (if \code{clusters = FALSE}).
#'
#' @references
#' Wiemann T (2023). "Optimal Categorical Instruments." <https://arxiv.org/abs/2311.17021>
#'
#' @export
#'
#' @examples
#' # Simulate simple dataset with n=800 observations
#' X <- rnorm(800) # continuous predictor
#' Z <- sample(1:20, 800, replace = TRUE) # categorical predictor
#' Z0 <- Z %% 4 # lower-dimensional latent categorical variable
#' y <- Z0 + X + rnorm(800) # outcome
#' # Compute kcmeans with four support points
#' kcmeans_fit <- kcmeans(y, cbind(Z, X), K = 4)
#' # Calculate in-sample predictions
#' fitted_values <- predict(kcmeans_fit, cbind(Z, X))
#' # Print sample share of estimated clusters
#' clusters <- predict(kcmeans_fit, cbind(Z, X), clusters = TRUE)
#' table(clusters)
predict.kcmeans <- function(object, newdata, clusters = FALSE, ...) {
  # Check whether additional features are included, compute X\pi if needed
  if (!is.null(object$pi)) {
    Z <- newdata[, object$which_is_cat]
    X <- newdata[, -object$which_is_cat, drop = FALSE]
    if(!clusters) Xpi <- X %*% object$pi
  } else {
    Z <- newdata
    Xpi <- 0
  }#IFELSE
  # Generate row-indices
  nobs <- length(Z)
  indx <- 1:nobs
  # Construct fitted values from cluster map
  fitted_mat <- merge(cbind(indx, Z), object$cluster_map,
                      by.x = 2, by.y = 1, all.x = TRUE)
  # Re-order by row-indices
  fitted_mat <- fitted_mat[order(fitted_mat[, 2]), -2]
  # Construct predictions
  if (clusters) {
    # Return estimated cluster assignment
    return(fitted_mat[, "cluster_x"])
  } else {
    # Replace unseen categories with unconditional mean of y - X\pi
    fitted_mat[is.na(fitted_mat[, "mean_xK"]), 5] <- object$mean_y
    # Construct and return fitted values
    fitted <- fitted_mat[, "mean_xK"] + Xpi
    return(fitted)
  }#IFELSE
}#PREDICT.KCMEANS
