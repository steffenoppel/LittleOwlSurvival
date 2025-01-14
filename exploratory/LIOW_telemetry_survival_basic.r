##########################################################################
#
# LITTLE OWL BIWEEKLY SURVIVAL ANALYSIS FROM TELEMETRY
#
##########################################################################
# written by Steffen Oppel, July 2023
# based on data by Marco Perrig
# stripped down very basic model to investigate why estimated survival is LOWER than observed survival


library(runjags)
library(tidyverse)
library(data.table)
library(lubridate)
library(tidyverse)
# library(geosphere)
filter<-dplyr::filter
select<-dplyr::select
library(MCMCvis)


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# LOAD DATA FROM PREPARED WORKSPACE
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
### data preparation moved to LIOW_telemetry_data_prep.r
try(setwd("C:/Users/sop/OneDrive - Vogelwarte/General - Little owls/ANALYSES/LittleOwlSurvival"),silent=T)
try(setwd("C:/STEFFEN/OneDrive - Vogelwarte/General - Little owls/ANALYSES/LittleOwlSurvival"),silent=T)
# renv::init()   ### need to re-run this when you add a new library that needs to be run on the server
# renv::snapshot()

load("data/LIOW_SURV_INPUT.RData")


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
########### PREPARATORY FUNCTIONS ####
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Function to create a matrix with information about known latent state z
known.state.cjs <- function(ch){
  state <- ch
  for (i in 1:dim(ch)[1]){
    n1 <- min(which(ch[i,]==1))
    n2 <- max(which(ch[i,]==1))
    state[i,n1:n2] <- 1
    state[i,n1] <- NA
  }
  state[state==0] <- NA
  return(state)
}

# Initial values 
# Function to create a matrix of initial values for latent state z
cjs.init.z <- function(ch,f){
  for (i in 1:dim(ch)[1]){
    if (sum(ch[i,])==1) next
    n2 <- max(which(ch[i,]==1))
    ch[i,f[i]:n2] <- NA
  }
  for (i in 1:dim(ch)[1]){
    ch[i,1:f[i]] <- NA
  }
  return(ch)
}

get.first <- function(x) min(which(x!=0))
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# SPECIFY SURVIVAL MODEL IN JAGS
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# based on BPA book Kery and Schaub 2012, Chapter 7


# Specify model in JAGS language
sink("models/LIOW_CJS_perfect_p.jags")
cat("
model {

# Priors and constraints
for (i in 1:nind){
   for (t in f[i]:(n.occasions)){
      phi[i,t] <- pow(mean.phi,1/26)   ## annual survival as 26th root of biweekly survival
      p[i,t] <- mean.p #* recap.mat[i,t] 
      } #t
   } #i
   
   mean.phi ~ dbeta(10, 35)                   # Prior for mean biweekly survival from Thorup et al. 2013, converted to beta
   mean.p ~ dunif(0.999, 1)                     # Prior for mean recapture during full effort periods

# sigma.p ~ dunif(0, 2)                      # Prior for standard deviation for random detection effect
# tau.p <- pow(sigma.p, -2)

# Likelihood 
for (i in 1:nind){
   # Define latent state at first capture
   z[i,f[i]] <- 1
   z.rep[i,f[i]] <- 1 # replicate z (true state)
   y.rep[i,f[i]] <- 1 # replicate y (data)
   for (t in (f[i]+1):n.occasions){
      # State process
      z[i,t] ~ dbern(phi[i,t-1] * z[i,t-1])
      z.rep[i,t] ~ dbern(phi[i,t-1] * z.rep[i,t-1]) # replicate z (true state)
      # Observation process
      y[i,t] ~ dbern(p[i,t] * z[i,t])
      y.rep[i,t] ~ dbern(p[i,t] * z.rep[i,t]) # replicate y (observations)

    
    } #t end
      #Derived parameters

        ## GOODNESS OF FIT TEST SECTION
        ## Discrepancy observed data
        E.obs[i] <- pow((sum(y[i,(f[i]+1):n.occasions]) - sum(p[i,(f[i]+1):(n.occasions)] * z[i,(f[i]+1):n.occasions])), 2) / (sum(p[i,(f[i]+1):n.occasions] * z[i,(f[i]+1):n.occasions]) + 0.001)

        ## Discrepancy replicated data
        E.rep[i] <- pow((sum(y.rep[i,(f[i]+1):n.occasions]) - sum(p[i,(f[i]+1):(n.occasions)] * z.rep[i,(f[i]+1):n.occasions])), 2) / (sum(p[i,(f[i]+1):(n.occasions)] * z.rep[i,(f[i]+1):n.occasions]) + 0.001)
        
    } #i end
      fit <- sum(E.obs[])
      fit.rep <- sum(E.rep[])
}
",fill = TRUE)
sink()


#### CURTAIL DATA AND PREPARE FOR MODEL #####
# CH<-CH[,1:28]
# recap.mat<-recap.mat[,1:28]
# f <- apply(CH, 1, get.first)

inits <- function(){list(z = cjs.init.z(CH, f),
                         mean.phi = rbeta(1, 10, 35),
                         mean.p = runif(1, 0, 1))}  


### FIND OCC WITH 0 detections
## cannot work because each column represents a different year
apply(CH[LIOW$year==2009,],2,sum)
apply(recap.mat[LIOW$year==2009,],2,max)

### ENSURE REPEATABLE SCALING OF SNOWMAT ##
INPUT <- list(y = CH, f = f,
              nind = dim(CH)[1],
              n.occasions = dim(CH)[2],
              recap.mat=ifelse(recap.mat==3,0,1),
              z = known.state.cjs(CH))

# Parameters monitored
parameters <- c("mean.phi","mean.p","deviance","fit","fit.rep")

# MCMC settings
nt <- 6
nb <- 200
nc <- 3
nad<-100
ns<-1000
ni<-1500

# Call JAGS from R
basic.model <- run.jags(data=INPUT, inits=inits, monitor=parameters,
                        model="C:/Users/sop/OneDrive - Vogelwarte/General - Little owls/ANALYSES/LittleOwlSurvival/models/LIOW_CJS_basic_p.jags",
                        n.chains = nc, thin = nt, burnin = nb, adapt = nad,sample = ns, 
                        method = "rjparallel") 


### very crude annual survival estimate (everything constant)
basic.model$summary$quantiles[1,c(1,3,5)]

### compare to actually OBSERVED survival
sum(apply(CH[,c(29:30)],1,max)) / dim(CH)[1]
sum(CH[,29]) / dim(CH)[1]



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# RE-RUN MODEL WITH INTERPOLATED INTERNAL ZEROs
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### ENSURE REPEATABLE SCALING OF SNOWMAT ##
CH.imp<-CH
for (d in 1:nrow(CH)){
  CH.imp[d,f[d]:l[d]]<-1
}
### check whether it worked
f<- apply(CH.imp, 1, get.first)
l<- apply(CH.imp, 1, get.last)
n<-apply(CH.imp,1,sum)
((l-f+1)/n)


INPUT.impute <- list(y = CH.imp, f = f,
              nind = dim(CH)[1],
              n.occasions = dim(CH)[2],
              recap.mat=ifelse(recap.mat==3,0,1),
              z = known.state.cjs(CH))

inits <- function(){list(z = cjs.init.z(CH, f),
                         mean.phi = rbeta(1, 10, 35),
                         mean.p = runif(1, 0.999, 1))}  

# Call JAGS from R
impute.model <- run.jags(data=INPUT.impute, inits=inits, monitor=parameters,
                        model="C:/Users/sop/OneDrive - Vogelwarte/General - Little owls/ANALYSES/LittleOwlSurvival/models/LIOW_CJS_perfect_p.jags",
                        n.chains = nc, thin = nt, burnin = nb, adapt = nad,sample = ns, 
                        method = "rjparallel") 

### very crude annual survival estimate (everything constant)
impute.model$summary$quantiles[1,c(1,3,5)]



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GOODNESS OF FIT ASSESSMENT
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
## VERY POORLY FITTING MODEL

## USING THE CALCULATED FIT VALUES FROM THE JAGS MODEL
OBS <- MCMCpstr(basic.model$mcmc, params=c("fit"), type="chains")
REP <- MCMCpstr(basic.model$mcmc, params=c("fit.rep"), type="chains")
GOF<-tibble(Rep=as.numeric(REP[[1]]),Obs=as.numeric(OBS[[1]])) %>%
  mutate(P=ifelse(Obs>Rep,1,0))

ggplot(GOF,aes(x=Rep,y=Obs, fill=P)) + geom_point(position=position_jitterdodge()) +
  geom_abline(intercept = 0, slope = 1) +
  theme(legend.position="none") +
  annotate("text",label=as.character(round(mean(GOF$P),2)),x=20,y=20,size=8, colour="firebrick")

mean(GOF$P)



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CALCULATE SURVIVAL MANUALLY
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

### THE DISCREPANCY OCCURS BECAUSE ONLY FEW INDIVIDUALS CONTRIBUTE TO THE FIRST FEW SURVIVAL ESTIMATES
## if all individuals started at occ 1 the product of occasion-specific survival and crude survival would be the same

man.surv<-as.numeric(rep(0,(dim(CH.imp)[2]-1)))
N.occ<-apply(CH.imp,2,sum)
for (occ in 2:dim(CH.imp)[2]){
  #man.surv[occ-1]<-apply(CH.imp[which(f<=(occ-1)),],2,sum)[occ]/apply(CH.imp[which(f<=(occ-1)),],2,sum)[occ-1]
  man.surv[occ-1]<-apply(CH.imp[which(f<=(1)),],2,sum)[occ]/apply(CH.imp[which(f<=(1)),],2,sum)[occ-1]
}
prod(man.surv)
sum(CH.imp[which(f<=(1)),30]) / dim(CH.imp[which(f<=(1)),])[1]



View(CH.imp)
