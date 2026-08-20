library(plumber)

pr <- plumb("plumber.R")
pr$run(port = 8040, host = "0.0.0.0")
