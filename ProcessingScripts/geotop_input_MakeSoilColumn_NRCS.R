## geotop_input_MakeSoilColumn.R
#' This script is intended to  create a soil input file for simulations
#' in GEOtop. The soil column will have two soil types: organic and mineral 
#' soil. Adjustable parameters will include the thickness and hydraulic
#' retention properties of each soil type.
#' 
#' The soil columns is structured as a series of uniform thickness layers for  
#' organic soil interval, and then linearly increasing thickness for the
#' mineral soil interval.

rm(list=ls())

# function to calculate theta (used to define wilting point and field capacity)
VG_ThetaFromHead <- function(head, ThetaR, ThetaS, alpha, n){
  # This is intended to take ThetaS [m3 m-3], ThetaR [m3 m-3], alpha [m-1], and
  # n [-] values and produce theta estimates for a vector of head [m].
  if (head >= 0){
    theta <- ThetaS
  } else {
    theta <- ThetaR + (ThetaS - ThetaR)/((1+(alpha*abs(head))^n)^(1-1/n))
  }
  
  return(theta)
}

# git directory for relative paths
#git.dir <- "C:/Users/Sam/WorkGits/Permafrost/ARF1D/"
git.dir <- "C:/Users/Sam/WorkGits/ARF1D/"

# path to save output soil file
out.path <- paste0(git.dir, "geotop_NRCS/soil/soilNRCS0001.txt")

# logical: should organic layer Ksat be decreased with depth?
decrease.org.Ksat <- F

# define soil layer properties
min.Dz   <- 10     # [mm] - thickness of organic soil layers
total.Dz <- 8000   # [mm] - total soil thickness
nsoilay  <- 60     # number of soil layers

## tunable soil parameters
# organic soil - using values from Jiang et al. (2015) SI for 1st layer
#   thermal conductivity & capacity from Kurylyk et al. (2016) WRR Table A1
org.z <- 100      # [mm] - thickness of organic soil (average of 3 wall face from NRCS soil pedons = 10 cm)
org.Ks <- 0.17    # [mm/s] - saturated hydraulic condutivity 
org.vwc_s <- 0.55  # [m3/m3] - saturated water content
org.vwc_r <- 0.01  # [m3/m3] - residual water content
org.VG_alpha <- 12.7*(1/1000) # [mm-1] - Van Genuchten alpha (Jiang et al. = 12.7 m-1)
org.VG_n <- 2.00       # [-] - Van Genuchten n
org.thermcond <- 0.25   # [W/m/K] - thermal conductivity of soil solids
org.thermcap <- 2.6E+6   # [J/m3/K] - thermal capacity of soil solids

# calculate field capacity and wilting point
org.vwc_fc <- VG_ThetaFromHead(-3.3, org.vwc_r, org.vwc_s, org.VG_alpha*1000, org.VG_n)
org.vwc_wp <- VG_ThetaFromHead(-150, org.vwc_r, org.vwc_s, org.VG_alpha*1000, org.VG_n)

# mineral soil - using values from Carsel & Parrish (1988) for silt loam based on NRCS soil pedons
#   thermal conductivity & capacity from Kurylyk et al. (2016) WRR Table A1
min.Ks <- 0.00125    # [mm/s] - saturated hydraulic condutivity 
min.vwc_s <- 0.41  # [m3/m3] - saturated water content
min.vwc_r <- 0.01  # [m3/m3] - residual water content
min.VG_alpha <- 2.0*(1/1000)  # [mm-1] - Van Genuchten alpha (convert from 12.7 m-1)
min.VG_n <- 1.41              # [-] - Van Genuchten n
min.thermcond <- 1.62         # [W/m/K] - thermal conductivity of soil solids
min.thermcap <- 2.0E+6        # [J/m3/K] - thermal capacity of soil solids

# calculate field capacity and wilting point
min.vwc_fc <- VG_ThetaFromHead(-3.3, min.vwc_r, min.vwc_s, min.VG_alpha*1000, min.VG_n)
min.vwc_wp <- VG_ThetaFromHead(-150, min.vwc_r, min.vwc_s, min.VG_alpha*1000, min.VG_n)

## figure out number of organic and mineral layers based on thicknesses
nsoilay.org <- round(org.z/min.Dz)
nsoilay.min <- nsoilay - nsoilay.org

## figure out increment to increase mineral soil layer thickness with depth
# coefficient for incrementing
incrcoeff <- 0.0
for (j in 1:(nsoilay.min-1)){
  # figure out total increment coefficient
  incrcoeff <- incrcoeff + j
}

# incrementing constant
incconst <- ((total.Dz-nsoilay.org*min.Dz) - (min.Dz*nsoilay.min))/incrcoeff

## build soil layers
df.out <- data.frame(Dz = numeric(length=nsoilay),
                     z.tot = NaN,
                     Kh = NaN,
                     Kv = NaN,
                     vwc_r = NaN,
                     vwc_s = NaN,
                     vwc_fc = NaN,
                     vwc_wp = NaN,
                     VG_alpha = NaN,
                     VG_n = NaN,
                     SS = NaN,
                     thermcond = NaN,
                     thermcap = NaN)
df.out$Dz[1] <- min.Dz
df.out$z.tot[1] <- min.Dz
df.out$Kh[1] <- org.Ks
df.out$Kv[1] <- org.Ks
df.out$vwc_r[1] <- org.vwc_r
df.out$vwc_s[1] <- org.vwc_s
df.out$vwc_wp[1] <- org.vwc_wp
df.out$vwc_fc[1] <- org.vwc_fc
df.out$VG_alpha[1] <- org.VG_alpha
df.out$VG_n[1] <- org.VG_n
df.out$thermcond[1] <- org.thermcond
df.out$thermcap[1] <- org.thermcap
for (j in 1:(nsoilay-1)){
  if ((j-1)<nsoilay.org){
    # organic layers
    df.out$Dz[j+1] <- min.Dz
    df.out$z.tot[j+1] <- df.out$z.tot[j] + df.out$Dz[j+1]
    
    if (decrease.org.Ksat){
      # make a linear relationship between depth and Ksat
      # this is based on data in the LitData_PeatHydraulicProperties.csv
      # file from Schwaerzel et al. (2006)
      df.scale <- data.frame(depth=c(75, 75, 75, 200, 200, 200, 270, 270, 270),  # mm
                             Ksat=c(3.88E-03, 1.62E-03, 4.83E-04,  # mm/s
                                    4.38E-04, 7.74E-04, 7.70E-04,
                                    4.75E-06, 2.89E-05, 1.06E-04))
      scale.slope <- coef(lm(log10(Ksat) ~ depth, df.scale))[2]  # this is the slope, in [(mm/s)/mm]
      
      # depth of center of this layer
      depth.center.mm <- df.out$z.tot[j+1] - df.out$Dz[j+1]/2
      
      # reduce based on distance from 0
      Ksat.depth <- 10^(log10(org.Ks)+scale.slope*depth.center.mm)
      if (Ksat.depth<min.Ks) Ksat.depth <- min.Ks   # don't let it drop below mineral soil Ks
      df.out$Kh[j+1] <- Ksat.depth
      df.out$Kv[j+1] <- Ksat.depth
      
    } else {
      df.out$Kh[j+1] <- org.Ks
      df.out$Kv[j+1] <- org.Ks
    }
    df.out$vwc_r[j+1] <- org.vwc_r
    df.out$vwc_s[j+1] <- org.vwc_s
    df.out$vwc_fc[j+1] <- org.vwc_fc
    df.out$vwc_wp[j+1] <- org.vwc_wp
    df.out$VG_alpha[j+1] <- org.VG_alpha
    df.out$VG_n[j+1] <- org.VG_n
    df.out$thermcond[j+1] <- org.thermcond
    df.out$thermcap[j+1] <- org.thermcap
  } else {
    # mineral soil
    df.out$Dz[j+1] <- min.Dz + (j-nsoilay.org)*incconst
    df.out$z.tot[j+1] <- df.out$z.tot[j] + df.out$Dz[j+1]
    df.out$Kh[j+1] <- min.Ks
    df.out$Kv[j+1] <- min.Ks
    df.out$vwc_r[j+1] <- min.vwc_r
    df.out$vwc_s[j+1] <- min.vwc_s
    df.out$vwc_fc[j+1] <- min.vwc_fc
    df.out$vwc_wp[j+1] <- min.vwc_wp
    df.out$VG_alpha[j+1] <- min.VG_alpha
    df.out$VG_n[j+1] <- min.VG_n
    df.out$thermcond[j+1] <- min.thermcond
    df.out$thermcap[j+1] <- min.thermcap
  }
}

# anything that does not vary based on depth
df.out$SS <- 1.00E-07       # Specific storativity - use default value

# # homogeneous VG properties, but not thermal
# df.out$Kh <- min.Ks
# df.out$Kv <- min.Ks
# df.out$vwc_r <- min.vwc_r
# df.out$vwc_s <- min.vwc_s
# df.out$VG_alpha <- min.VG_alpha
# df.out$VG_n <- min.VG_n
# 
# # homogeneous thermal properties, but not VG
# df.out$thermcond <- min.thermcond
# df.out$thermcap <- min.thermcap

# save output file
write.csv(df.out, out.path, quote=F, row.names=F)

## make a plot
#ggplot(df.out, aes(x=Kh, y=z.tot)) + scale_y_reverse() + geom_point()
#ggplot(df.scale, aes(x=log10(Ksat), y=depth)) + scale_y_reverse() + geom_point() + stat_smooth(method="lm")
