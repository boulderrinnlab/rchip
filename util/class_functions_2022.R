#' A function to multiply two numbers
#'
#' @description 
#' This function will multiply the input values of X and Y
#' 
#' @param x one number you'd like to multiply
#' y the other number you'd like to multiply
fun <- function(x, y) {
  ans <- x * y
  return(ans)
}



#' import peak .bed files as a list 
#' 
#' @description 
#' this function will take each peak file and name them by the DBP
#' and return a list of GRanges peaks for each ChiPseq experiment
#' 
#' @param consensus_file_path the path to each peak file
#' 

import_peaks <- function(consensus_file_path = "/scratch/Shares/rinnclass/CLASS_2022/data/peaks") {
  
  # Setting some variables needed in main part of function (same as above -- peak_files & tf_name)
  peak_files <- list.files(consensus_file_path, full.names = T)
  
  # Make an object with each TF name for indexing and merging later
  tf_name <- sapply(peak_files, function(x){
    y <-  str_extract(x, "([^\\/]+$)")
    unlist(strsplit(y, "_"))[[1]]
  })
  
  # Here is the heart of the function that will import each file as GRanges (we can use for overlaps)
  # takes 
  
  peak_list <- c()
  for(i in 1:length(peak_files)) {
    # Import peak files
    peaks <- rtracklayer::import(peak_files[i])
    # Append this GRanges object to the of the list.
    peak_list <- c(peak_list, peaks)
    # Name the list elements by their TF name (we just made above)
    names(peak_list)[length(peak_list)] <- tf_name[i]
  }
  return(peak_list)
}



#' Intersect peaks from replicate chip-seq peak files 
#' 
#' @description 
#' this function will take each peak file and perform 
#' fingOVerlaps to produce all the indicies for overlaps 
#' this is further used in create_consensus_peaks function

#' 
#' @param peak_list which is produced in import_peaks function
#' 

intersect_peaks <- function(peak_list) {

combined_peaks <- peak_list[[1]]
for(i in 2:length(peak_list)) {
  suppressWarnings(pl_ov <- findOverlaps(combined_peaks, peak_list[[i]]))
  pl1 <- combined_peaks[unique(pl_ov@from)]
  pl2 <- peak_list[[i]][unique(pl_ov@to)]
  suppressWarnings(combined_peaks <- GenomicRanges::reduce(union(pl1, pl2)))
  
}
return(combined_peaks)
}



#' read peaks function: filter to cannonical chr 
#' 
#' @description 
#' this function will filter each peak file to only cannonical chr.


#' 
#' @param broad_peak_file which is produced in import_peaks function
#' 

read_peaks <- function(broad_peak_file, filter_to_canonical_chr = TRUE) {
  dat <- read.table(broad_peak_file, sep = "\t")
  if(filter_to_canonical_chr == TRUE) {
    dat <- dat[dat$V1 %in% c(paste0("chr", 1:22), "chrM", "chrX", "chrY"),]
  }
  gr <- GRanges(seqnames = dat$V1,
                ranges = IRanges(start=dat$V2,end=dat$V3))
  return(gr)
}




#' CREATE CONSENSUS PEAKS FUNCTION 
#' 
#' @description 
#' this function will use the functions above
#' read_peaks and intersect_peaks
#' It will filter to cannonical chromosomes
#' find overlapping peaks in all replicates for a given tf (dbp)
#' merge these into one peak


#' 
#' @param broadpeakfilepath which the file path to all the peak files
#' 


create_consensus_peaks <- function(broadpeakfilepath = "/scratch/Shares/rinnclass/CLASS_2022/data/peaks/") {
  
  # For now we can set broadpeakfilepath
  
  # broadpeakfilepath <- "/Shares/rinn_class/data/CLASS_2022/class_exeRcises/analysis/11_consensus_peak_exercise"
  
  # making a list of file paths to the (similar to import_peaks function)
  fl <- list.files(broadpeakfilepath, 
                   full.names=TRUE)
  fl <- fl[grep("peaks.broadPeak", fl)]
  
  # getting a DBP name for same index as each file path
  tf_name <- sapply(fl, function(x){
    y <-  str_extract(x, "([^\\/]+$)")
    unlist(strsplit(y, "_"))[[1]]
  })
  
  
  # making sure there is a replicate and creating "unique_tf" index
  # This will be used in a forloop
  tf_df <- data.frame(table(tf_name)) %>%  # data.frame(table(tf_name))
    filter(Freq > 1)
  unique_tf <- as.character(tf_df$tf_name) # unique_tf
  
  
  # Now a nested for loop (2 for loops) to make GRanges of peak files.
  # This is similar to read_peaks
  consensus_peaks <- list()
  for(i in 1:length(unique_tf)) {
    
    # load all the peak files corresponding to this DBP[i] in unique_tf.
    # tf <- unique_tf[1] -- allows us to look at output
    tf <- unique_tf[i]
    print(tf)
    # indexing unique DBP name to file path (e.g., first 8 are CTCF files)
    tf_index <- grep(tf, tf_name)
    # takes the TF name and grabs the index in fl for those replicates
    tf_files <- fl[tf_index]
    
    # now make a list of GRanges in a peak_list using another for loop
    # READ_PEAKS being used 
    peak_list <- c()
    for(j in 1:length(tf_files)) {
      # See the read peaks function to know what subfunctions are called.
      peak_list <- c(peak_list, read_peaks(tf_files[j]))
      # same read peaks function and we now have each DBP indexed in tf_files
    }
    
    # READ_PEAKS now being used
    # filtering chromosomes -- redundant since read peaks does this too -- oh well.
    canonical_chr <- c(paste0("chr", 1:22), "chrM", "chrX", "chrY")
    for(i in 1:length(peak_list)) {
      peak_list[[i]] <-peak_list[[i]][which(seqnames(peak_list[[i]]) %in% canonical_chr)]
    }
    
    # Now we use intersect_peaks functino to find overlaps 
    # INTERSECT_PEAKS now being used
    final_peakset <- intersect_peaks(peak_list = peak_list)
    if(length(final_peakset) > 0) {
      final_peakset$name <- paste0(tf, "_", 1:length(final_peakset))
    }
    
    consensus_peaks <- c(consensus_peaks, list(final_peakset))
    names(consensus_peaks)[length(consensus_peaks)] <- tf
  }
  return(consensus_peaks)
}



#' Profile TSS
#' 
#' @description 
#' description


#' 
#' @param peaks @param promoter_gr @param window-size the file path to all the peak files
#' 
#' 
profile_tss <- function(peaks, 
promoters_gr,
upstream = 3e3,
downstream = 3e3) {
  
  # performing coverage function
  # this converst each chromosome to RLE
  # where 0 is no peak and 1 is a peak
  # NOTE: chrm end will be at end of last peak.
  peak_coverage <- coverage(peaks)
  
  # elementNROWs will find the end of the last peak.
  # this will result in the "effective length" of the chr
  coverage_length <- elementNROWS(peak_coverage)
  
  # Defining a GRanges using the effective length of chr
  # from "coverage_length" above.
  coverage_gr <- GRanges(seqnames = names(coverage_length),
                         # make IRanges for each chromosome
                         IRanges(start = rep(1, length(coverage_length)), 
                                 end = coverage_length))
  
  # defining the promoters using using subsetByOverlaps (GRanges)
  # This will map the promoters to our new chromosome GRanges (coverage_gr)
  promoters_gr <- subsetByOverlaps(promoters_gr, 
                                   coverage_gr, 
                                   type="within", 
                                   ignore.strand=TRUE)
  
  # making sure the chromosomes represented are used
  # An error would occur if a chromosome was indexed but had no peaks
  chromosomes <- intersect(names(peak_coverage), 
                           unique(as.character(seqnames(promoters_gr))))
  
  # Reducing peak_coverage (RLE of peaks and genome)
  # to only chromosomes represented by peaks
  peak_coverage <- peak_coverage[chromosomes]
  
  # converting to InterRangesList. This will allow us to use "views" function.
  # Our "peak_coverage" is in RLE. So we will make our promoters in a way that 
  # can be mapped to RLE and convert back to 1 and 0 in a given promoter window.
  promoters_ir <- as(promoters_gr, "IntegerRangesList")[chromosomes]
  
  # Views function allows us to take promoters integerRangesList and 
  # "view" the peak coverage (RLE) as 1 and 0 using View apply
  # so just matching promoter_ir and peak_coverage for now
  promoter_peak_view <- Views(peak_coverage, promoters_ir)
  
  # We use viewApply function to convert RLE in peak_coverage to a vector of 1 and 0
  # we use lapply to do this over each chromosomes 
  promoter_peak_view <- lapply(promoter_peak_view, function(x) t(viewApply(x, as.vector)))
  
  # We can see that promoter_peak_view is now a list a matrix of vectors for each chromosome
  # rows are number of peaks and cols are position -3Kb to + 3Kb
  promoter_peak_matrix <- do.call("rbind", promoter_peak_view)
  
  # We are identifying all the - strand promoters in promoters_gr
  minus_idx <- which(as.character(strand(promoters_gr)) == "-")
  
  # reversing the order from 6,000 - 1 to 1- 6000
  promoter_peak_matrix[minus_idx,] <- promoter_peak_matrix[minus_idx, ncol(promoter_peak_matrix):1]
  
  # eliminating promoters with no binding 
  promoter_peak_matrix <- promoter_peak_matrix[rowSums(promoter_peak_matrix) > 1,]
  
  # summing all the vectors of a given DBP to the promoter window
  peak_sums <- colSums(promoter_peak_matrix)
  
  # calculating the density at each position in the promoter window
  peak_dens <- peak_sums/sum(peak_sums)
  
  # making it go from -3K to + 3K and creating a df
  metaplot_df <- data.frame(x = -upstream:(downstream-1),
                            dens = peak_dens)
  
  return(metaplot_df)
}
#' 


