#!/usr/bin/Rscript

# See tutorial at https://benjjneb.github.io/dada2/tutorial.html.  This script will
# QC and identify valid unique reads, then assemble.  It will execute on all files in
# the directory "multiplexed", and create the directories "filtered", and "merged".
# The Python script deunique_dada2.py should be used to inflate all of the output tables
# into redundant fasta files for paprica.

library(dada2)

path <- 'demultiplexed'
gene <- '16S'

#fnFs <- sort(list.files(path, pattern = 'Mock.*-R1.fastq', full.names = T))
#fnRs <- sort(list.files(path, pattern = 'Mock.*-R2.fastq', full.names = T))

fnFs <- sort(list.files(path, pattern = '-R1.fastq', full.names = T))
fnRs <- sort(list.files(path, pattern = '-R2.fastq', full.names = T))

sample.names <- sapply(strsplit(basename(fnFs), "-"), `[`, 1)

pdf(paste0(path, '/', 'quality_profiles.pdf'), width = 6, height = 6)

for(i in 1:length(fnFs)){
	print(plotQualityProfile(fnFs[i]))
	print(plotQualityProfile(fnRs[i]))
}
	
dev.off()

file_path <- file.path(paste0(path, '/','filtered')) # Place filtered files in filtered/ subdirectory
filtFs <- file.path(file_path, paste0(sample.names, "_R1.filt.fastq.gz"))
filtRs <- file.path(file_path, paste0(sample.names, "_R2.filt.fastq.gz"))

## multithreading only useful if multiple fastq files

out <- filterAndTrim(fnFs,
	filtFs,
	fnRs,
	filtRs,
	multithread = T,
#	minQ = 20,
#	truncQ = 30,
	trimLeft = 10,
	truncLen = 140,
	verbose = T)

plotQualityProfile(filtFs[1])

## need distribution of lengths for filtFs and filtRs
	
errF <- learnErrors(filtFs, multithread=TRUE)
errR <- learnErrors(filtRs, multithread=TRUE)

pdf(paste0(path, '/', 'error_rates.pdf'), width = 6, height = 6)
print(plotErrors(errF, nominalQ = T))
print(plotErrors(errR, nominalQ = T))
dev.off()

derepFs <- derepFastq(filtFs, verbose = T)
derepRs <- derepFastq(filtRs, verbose = T)

## wouldn't it make more sense to assemble here?

names(derepFs) <- sample.names
names(derepRs) <- sample.names

dadaFs <- dada(derepFs, err=errF, multithread=TRUE)
dadaRs <- dada(derepRs, err=errR, multithread=TRUE)

mergers <- mergePairs(dadaFs,
                      derepFs,
                      dadaRs,
                      derepRs,
                      maxMismatch = 0,
                      verbose=TRUE)

## ZymoBIOMICS Microbial Community Standard should have 8 bacterial strains, 2 fungal strains,
## so if you have more than 10 strains you probably QC'd insufficiently.

## Above method still produces reads of different lengths after merge.  Generate a function to
## evaluate distribution of read lengths and eliminate anything that is not correct length.

check.length <- function(mergers){
  for(name in names(mergers)){
    temp <- mergers[[name]]
    temp.lengths <- unlist(lapply(temp$sequence, nchar))
    temp.lengths.expand <- rep(temp.lengths, temp$abundance)
    hist(temp.lengths.expand, breaks = 100)
    
    temp[, 'length'] = temp.lengths
    mergers[[name]] = temp
  }
  return(mergers)
}

## Write fasta file for all reads at or below the expected read length.

max.read.length <- 155

dir.create(paste0(path, '/', 'merged_2'))

for(name in names(mergers)){
  temp <- mergers[[name]]
  temp <- temp[which(temp$length <= max.read.length),]
	write.csv(mergers[[name]], paste0(path, '/merged_2/', name, '.', gene, '.csv'), quote = F, row.names = F)
}
