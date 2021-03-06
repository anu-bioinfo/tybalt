# Pan-Cancer Variational Autoencoder
# Gregory Way 2018
# scripts/util/simulate_expression.R
#
# Functions to facilitate gene expression data simulation
#
# Usage: import only 
# source("scripts/util/simulate_expression.R")

sampleGroupMatrix <- function(num_samples, mean_matrix, sd_matrix) {
  # Sample different "groups" based on mean and standard deviation matrices
  #
  # Usage:
  # Called within the function `getSimulatedExpression()` but can also be used
  # to sample a given number of data points with the given mean and sd matrices
  #
  # Arguments:
  # num_samples - the number of samples to simulate
  # mean_matrix - a matrix of different group means
  # sd_matrix - a matrix of different group standard deviations
  #
  # The rows of each matrix indicate group specific data (group mean or group
  # standard deviation) and the columns represent different group features.
  # (nrow = num groups) (ncol = num features that describe each group)
  #
  # Return:
  # list of length 2:
  #
  # The 1st element is the group specific feature matrix storing
  # length(num_samples) rows and ncol(mean_matrix) columns. Each column
  # represents a feature sampled from a normal distribution with the mean
  # provided by the columns of `mean_matrix` and standard deviation provided
  # by the columns of `sd_matrix` The number of rows in mean and sd matrices
  # represent the number of groups.
  #  
  # The 2nd element is a vector of group labels ("a", "b", "c", etc.)

  group_df <- c()
  group_name <- letters[1:nrow(mean_matrix)]
  for (param_idx in 1:ncol(mean_matrix)) {
    mean_vector <- mean_matrix[, param_idx]
    sd_vector <- sd_matrix[, param_idx]

    group_vector <- rnorm(num_samples, mean = mean_vector, sd = sd_vector)
    group_df <- cbind(group_df, group_vector)
  }

  num_repeat <- num_samples %/% length(group_name)
  num_remainder <- num_samples %% length(group_name)

  labels <- rep(group_name, num_repeat)
  
  if (num_remainder > 0) {
    labels <- c(labels, group_name[1:num_remainder])
  }
  
  colnames(group_df) <- paste('group', seq(1, ncol(group_df)), sep = "_")
  group_df <- tibble::as_data_frame(group_df)

  return_list <- list(group_df, labels)
  return(return_list)
}


sampleCellMatrix <- function(num_samples, cell_mean_matrix, cell_sd_matrix) {
  # Sample "cell-types" and then add together with different proportions
  #
  # Usage:
  # Called within the function `getSimulatedExpression()` but can also be used
  # to sample a given number of data points with the given mean and sd matrices
  #
  # Arguments:
  # num_samples - the number of samples to simulate
  # cell_mean_matrix - a matrix of cell-type means
  # cell_sd_matrix - a matrix of cell-type standard deviations
  #
  # Each matrix represents features (columns) describing cell-types (rows)
  # (Currently supports only two cell-types)
  #
  # Return:
  # list of length 2 - 1st element is the cell-type mixing data
  #                  - 2nd element is the ground truth cell-type proportion

  # Loop through specific input artificial "cell-types"
  cell_type_params <- list()
  for (cell_type_idx in 1:nrow(cell_mean_matrix)) {

    # loop through specific input cell-type features
    cell_type_feature <- c()
    for (cell_feature_idx in 1:ncol(cell_mean_matrix)) {

      # Obtain and sample from input parameters specific to cell-type feature
      mean_cell <- cell_mean_matrix[cell_type_idx, cell_feature_idx]
      sd_cell <- cell_sd_matrix[cell_type_idx, cell_feature_idx]

      cell_type_vector <- rnorm(num_samples, mean = mean_cell, sd = sd_cell)
      cell_type_feature <- cbind(cell_type_feature, cell_type_vector)
    }

    # Save each feature in internal list
    cell_type_params[[cell_type_idx]] <- cell_type_feature
  }

  # Uniform sampling between 0 and 1 represents random mixing proportions
  rand_cell_type_1 <- runif(num_samples, min = 0, max = 1)
  rand_cell_type_2 <- 1 - rand_cell_type_1
  cell_type_prop_list <- list(rand_cell_type_1, rand_cell_type_2)

  # Loop over sampled cell-type parameters (columns, or features, of input)
  for (cell_idx in 1:length(cell_type_params)) {

    # Perform element-wise multiplication 
    cell_type_params[[cell_idx]] <- cell_type_prop_list[[cell_idx]] * 
      cell_type_params[[cell_idx]]
  }

  # Add mixing proportions of cell-type together
  cell_type_df <- cell_type_params[[1]] + cell_type_params[[2]]

  colnames(cell_type_df) <- paste('cell_type',
                                  seq(1, ncol(cell_type_df)), sep = "_")
  cell_type_df <- tibble::as_data_frame(cell_type_df)

  return_list <- list(cell_type_df, rand_cell_type_1)
  return(return_list)
}


getSimulatedExpression <- function(n, mean_df, sd_df, r, func_list, b,
                                   cell_type_mean_df, cell_type_sd_df,
                                   seed, zero_one_normalize = TRUE,
                                   concat = FALSE) {
  # Obtain a matrix with simulated parameters. The matrix dimensions will be:
  # n by p, where p = ncol(mean_df) + r + length(func_list) + b +
  #                   ncol(cell_type_mean_df)
  #
  # Usage:
  #             simulated_data <- getSimulatedExpression(<args>)
  #
  # This will output a matrix of samples by features that can be used to
  # evaluate compression algorithms in a variety of tasks
  #
  # Arguments:
  # n - integer indicating the total number of samples
  # mean_df - matrix of means describing groups
  # sd_df - matrix of standard deviations describing groups
  #         for mean and sd, ncol = number of features, nrow = number of groups
  # r - the number of random noise parameters
  # func_list - each element in the list stores a function to apply to a
  #             random noise sampling (each element indicates a single param)
  # b - the number of presence/absence features (independent from group)
  #     (value is either 0, or is sampled from a standard normal)
  # cell_type_mean_df - matrix of means describing artificial cell-types
  # cell_type_sd_df - matrix of standard deviations describing cell-types
  #       Each row represents different cell types (only 2 currently supported)
  #       Each column represents features describing the cell types
  # seed - add random seed as required argument
  # zero_one_normalize - boolean to zero one normalize simulated features
  # concat - boolean to return combined output if TRUE, defaults to list output
  #
  # Return:
  # List of length 2: The first element is the simulated data matrix
  #                   The second element is important metadata including group
  #                       membership, cell type proportion, and the domain of
  #                       the input functions.
  
  require(tibble)
  require(dplyr)

  set.seed(seed)

  # Extract Group Features
  if (sum(mean_df + sd_df) != 0) {
    if (all(dim(mean_df) != dim(sd_df))) {
      stop("provide the same number of mean and standard deviation parameters")
    } else {
      group_params <- sampleGroupMatrix(n, mean_df, sd_df)
      group_df <- group_params[[1]]
      group_info <- group_params[[2]]
    } 
  } else {
      group_df <- c()
      group_info <- c()
  }

  # Get Random Noise Features
  rand_df <- c()
  if (r > 0) {
    for (rand_idx in 1:r) {
      rand_vector <- runif(n, min = 0, max = 1)
      rand_df <- cbind(rand_df, rand_vector)
    }
    colnames(rand_df) <- paste('random', seq(1, ncol(rand_df)), sep = "_")
    rand_df <- tibble::as_data_frame(rand_df)
  }

  # Get Continuous Function Features
  cont_df <- c()
  cont_other_df <- c()
  if (length(func_list) > 0) {
    for (cont_idx in 1:length(func_list)) {
      continuous_rand_x <- runif(n, min = -1, max = 1)
      continuous_rand_y <- func_list[[cont_idx]](continuous_rand_x)
      
      cont_df <- cbind(cont_df, continuous_rand_y)
      cont_other_df <- cbind(cont_other_df, continuous_rand_x)
    }
    colnames(cont_df) <- paste('continuous', seq(1, ncol(cont_df)), sep = "_")
    cont_df <- tibble::as_data_frame(cont_df)
    
    colnames(cont_other_df) <- paste('continuous_domain',
                                     seq(1, ncol(cont_other_df)), sep = "_")
    cont_other_df <- tibble::as_data_frame(cont_other_df)
  }

  # Get Presence/Absence of a Features
  pres_df <- c()
  if (b > 0) {
    for (pres_idx in 1:b) {
      rand_presence <- rnorm(n, mean = 3, sd = 0.5)
      rand_zeroone <- sample(c(0, 1), n, replace = TRUE)
      
      rand_presence <- rand_presence * rand_zeroone
      pres_df <- cbind(pres_df, rand_presence)
    }
    colnames(pres_df) <- paste('presence', seq(1, ncol(pres_df)), sep = "_")
    pres_df <- tibble::as_data_frame(pres_df)
  }

  # Get cell-type Features
  if (sum(cell_type_mean_df + cell_type_sd_df) != 0) {
    if (all(dim(cell_type_mean_df) != dim(cell_type_sd_df))) {
      stop("provide the same cell-type parameter dimensions")
    } else {
      # This will generate cell-types and then automatically simulate
      # differential cell-type proportion
      cell_type_info <- sampleCellMatrix(n, cell_type_mean_df, cell_type_sd_df)
      cell_type_df <- cell_type_info[[1]]
      cell_type_proportion <- cell_type_info[[2]]
    }
  } else {
    cell_type_df <- c()
    cell_type_proportion <- c()
  }

  # Merge Features
  feature_df <- dplyr::bind_cols(group_df, rand_df, cont_df, pres_df,
                                 cell_type_df)
  other_df <- dplyr::tibble("groups" = group_info,
                            "cell_type_prop" = cell_type_proportion)
  other_df <- dplyr::bind_cols(other_df, cont_other_df)

  # Normalize data by zero-one-normalization
  if (zero_one_normalize) {
    zeroonenorm <- function(x){(x - min(x)) / (max(x) - min(x))}
    feature_df <- apply(feature_df, MARGIN = 2, FUN = zeroonenorm)
    feature_df <- tibble::as_data_frame(feature_df)
  }

  if (concat) {
    return_obj <- dplyr::bind_cols(feature_df, other_df)
  } else {
    return_obj <- list(features = feature_df, other = other_df)
  }
  
  return(return_obj)
}
