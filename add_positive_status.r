source("https://gist.githubusercontent.com/mfoll/a4dfbb92068dc559f130/raw/714dc8c2e97987fd4385dcef2722b3ef986d38d6/get_vcf_data.r")

args <- commandArgs(TRUE)
parseArgs <- function(x) {
  res = strsplit(sub("^--", "", x), "=")
  if(length(unlist(res))==1) res[[1]][2]=""
  return(res)
}
argsL <- as.list(as.character(as.data.frame(do.call("rbind", parseArgs(args)))$V2))
names(argsL) <- as.data.frame(do.call("rbind", parseArgs(args)))$V1
args <- argsL;rm(argsL)

if(is.null(args$table) | is.null(args$vcf)) {
  cat("

      Method: add a status to each entry in the --table input: TP if present in the VCF and FP if not. Remove the entry if
              not validate requirements (coverage)

      Mandatory arguments:
      --table=file_name           - annotated table file to add a status
      --vcf=file_name             - VCF file to use for status computations

      Optional argumets:
      --min_qval_vcf=20           - minimum q-value in the VCF to consider a variant
      --min_qval_table=50         - minimum q-value in the table to consider a variant
      --min_dp_table=20           - minimum DP in the table to check for positive status
      --variable_to_plot          - list of variables in the table to plot, depending on FP/TP status 
                                    e.g. --variable_to_plot=RVSB,ERR
      --to_log10                  - list of variables in the table to transform in log10 scale (convenient for plots)
                                    e.g. --to_log10=ERR
      --reformat_indels           - reformat VCF indels: from 'chr1 1 A AT' to 'chr1 1 - T'
      --keep_unrare               - do not remove variant if popfreqmax > 10% or allelic frequency > 10%
      --help                      - print this text

      example: add_positive_status.r --table=test_annotated.txt --vcf=test.vcf \n\n")
  q(save="no")
}

if(is.null(args$min_qval_vcf)) {min_qval_vcf=20} else {min_qval_vcf=as.numeric(args$min_qval_vcf)}
if(is.null(args$min_qval_table)) {min_qval_table=50} else {min_qval_table=as.numeric(args$min_qval_table)}
if(is.null(args$min_dp_table)) {min_dp_table=20} else {min_dp_table=as.numeric(args$min_dp_table)}
if(is.null(args$variable_to_plot)) {variable_to_plot=NULL} else {variable_to_plot=unlist(strsplit(args$variable_to_plot,","))}
if(is.null(args$to_log10)) {to_log10=NULL} else {to_log10=unlist(strsplit(args$to_log10,","))}
if(is.null(args$reformat_indels)) {reformat_indels=FALSE} else {reformat_indels=TRUE}
if(is.null(args$keep_unrare)) {keep_unrare=FALSE} else {keep_unrare=TRUE}

table = read.table(args$table, quote="\"", stringsAsFactors=F, sep="\t", header=T)

# remove entry with QVAL_INV>50 in the table

table = table[which(table$QVAL_INV<50 | is.na(table$QVAL_INV)),]

for(v in to_log10) table[,v] = log10(table[,v])

vcf = read.table(args$vcf,stringsAsFactors=F,header=F,sep="\t")

# get VCF column names
con = file(args$vcf) ; open(con) ; h=""
while ( ! grepl("#CHROM", h)) {
  h = readLines(con, n = 1, warn = FALSE)
} ; close(con) 
colnames(vcf) = unlist(strsplit(h, "\t"))

# reformat indels
if(reformat_indels){
  dels = which(nchar(vcf$REF)>1)
  vcf[dels,"ALT"] = "-"
  vcf[dels,"REF"] = substr(vcf[dels,"REF"], 2, nchar(vcf[dels,"REF"]))
  vcf[dels,"POS"] = vcf[dels,"POS"] + 1
  ins = which(nchar(vcf$ALT)>1)
  vcf[ins,"REF"] = "-"
  vcf[ins,"ALT"] = substr(vcf[ins,"ALT"], 2, nchar(vcf[ins,"ALT"]))
}

# remove unrare variants
table$ExAC_nontcga_Max = apply(table[,which(grepl("ExAC_nontcga", colnames(table)) & !grepl("_ALL",colnames(table)))],
                               1, max)
if(!keep_unrare) table = table[which( (is.na(table$ExAC_nontcga_Max) | table$ExAC_nontcga_Max<0.1 ) & table$VF<0.1),]

# correct table indel notation
table[which(table$Ref == 0), "Ref"] = "-"
table[which(table$Alt == 0), "Alt"] = "-"

##### add the postive status ####

table$status = "FP"

table[which(table$coverage < min_dp_table | is.na(table$coverage)),"status"] = NA

table_test_if_FP = which(!is.na(table$status)) # if coverage ok we test if TP/FP
res = unlist(lapply(table_test_if_FP, function(i) {
  dat_table = table[i,]
  dat = vcf[which(vcf$`#CHROM`== dat_table$Chr & vcf$POS == dat_table$Start & vcf$REF == dat_table$Ref & vcf$ALT == dat_table$Alt ), c("FORMAT",dat_table$SM)]
  if(dim(dat)[1]!=0){
    qval = get_genotype(as.character(dat[2]), as.character(dat[1]),"QVAL")
    qval_inv = get_genotype(as.character(dat[2]), as.character(dat[1]),"QVAL_INV")
    if(!is.na(qval) & qval >= min_qval_vcf) { return("TP") } else {
      if(!is.na(qval_inv) & qval_inv <= min_qval_vcf) { return("TP") } else {
        return("FP")
      }
    }
  } else { return("FP") }
})) 
table[table_test_if_FP,"status"] = res

table = table[which(!is.na(table$status)),]

if(!is.null(variable_to_plot)){
  pdf("TP_FP_variables.pdf", 12.5, 5)
  par(mfrow=c(1,3))
  for(v in variable_to_plot){
    hist(as.numeric(table[,v]), br=20, main=v, ylab="counts", xlab=v, col=adjustcolor("darkblue",0.75), border="darkblue")
    hist(as.numeric(table[which(table$status=="TP"),v]), br=20, main=v, ylab="counts", xlab=v, col=adjustcolor("darkgreen",0.75), border="darkgreen")
    hist(as.numeric(table[which(table$status=="FP"),v]), br=20, main=v, ylab="counts", xlab=v, col=adjustcolor("darkred",0.75), border="darkred")
  }
  dev.off()
}

write.table(table, file=paste(paste(gsub(".txt","",args$table),"status",sep="_"),
                              ".txt",sep=""), quote=F, sep="\t")
