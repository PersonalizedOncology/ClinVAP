#!/usr/bin/env Rscript --no-save --no-restore --no-init-file --no-site-file

# reporting.R
# Julian Heinrich (julian@joules.de)
# Bilge Sürün (sueruen@informatik.uni-tuebingen.de)
#
# This script parses a vcf file and generates two a docx file containing information about the most
# relevant mutations found in the input vcf that can be used for
# clinical reporting.

library(futile.logger)
library(tryCatchLog)

# Create a new logger object.
logger <- log4r::create.logger()
# Set the logger's file output.
log4r::logfile(logger) <- '/tmp/base.log'

# To get R's log messages

flog.appender(appender.file('/tmp/check_points.log'))

# packages are installed within the docker image. 
tryCatchLog::tryLog({
  list.of.packages <- c("dplyr", "dtplyr", "tidyr", "stringr", "splitstackshape", "optparse", "readr", "RCurl", "devtools", "tidyjson", "VariantAnnotation","fs")
  lapply(list.of.packages, library, character.only=T)
})

# set this manually to run code interactively
#debug <- TRUE
debug <- FALSE

options(warn=1)

# parse command-line parameters
option_list = list(
  optparse::make_option(c("-f", "--file"), type = "character", help = "the input file in vcf format", default = NULL),
  optparse::make_option(c("-r", "--report"), type = "character", help = "the file name for the detailed output report", default = NULL),
  optparse::make_option(c("-d", "--database"), type= "character", help= "Where the MyDrug data is to be found. Required for Singularity only.", default= NULL),
  optparse::make_option(c("-m", "--metadata"), type = "character", help = "metadata json file, to integrate patient info into reulting json if present", default = NULL),
  optparse::make_option(c("-g", "--genome"), type = "character", help = "human genome assembly identifier", default = NULL),
  optparse::make_option(c("-c", "--civic38"), type = "character", help = "path to GRCh38 mapped CIViC db ", default = NULL)
)

opt_parser <- optparse::OptionParser(option_list = option_list)
opt <- optparse::parse_args(opt_parser)

# define input, output and database variables
tryLog({
  vcfFile <- opt$file
  reportFile <- opt$report
})

#  checks of input VCF
if (!debug && (is.null(opt$file) || !file.exists(opt$file))) {
  optparse::print_help(opt_parser)
  log4r::level(logger) <- 'ERROR'  
  log4r::error(logger, "Input file is not provided.")
  log4r::error(logger, "The process is terminated.")
  file.rename("/tmp/base.log", "/tmp/no_input.log")
  stop()
  #  stop("Please supply a valid input file")
} else {
  log4r::level(logger) <- 'INFO'
  messages = paste(opt$file, "is provided as input file")
  log4r::info(logger, messages)
  new_log = paste0(opt$file,"_base.log")
  file_move("/tmp/base.log", new_log)
  log4r::logfile(logger) <- new_log
}

# checks of output file command-line option
if (!exists('reportFile') || is.null(reportFile)) {
  reportFile <- paste(tools::file_path_sans_ext(vcfFile), "json", sep=".")
  msg <- paste("Invalid output file or option not given. Using", reportFile)
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, msg)
  print(msg)
}

# checks of database command-line option
if (is.null(opt$database)) {
  log4r::level(logger) <- 'INFO'  
  log4r::info(logger, "Database dump is not provided. The program will seek for the database on localhost.")
} else {
  dataFile <- opt$database
  log4r::level(logger) <- 'INFO'
  messages = paste(opt$database, "Database dump is provided. Application will not seek for database on localhost")
  log4r::info(logger, messages)
}

if (is.null(opt$metadata)) {
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "Patient metadata file is not found. Patient info table will be empty.")
} else {
  metaData <- opt$metadata
  log4r::level(logger) <- 'INFO'
  messages = paste(opt$metada, " is provided. It will be rendered into Patient info table")
  log4r::info(logger, messages)
  # read metadata
  patient_info <- jsonlite::fromJSON(opt$metadata)
  attach(patient_info)
}

# Collects the data from CiVIC and returns a list with two data frames for genes and evidence.
civic_source = "https://civicdb.org/downloads/01-Jan-2019/01-Jan-2019-ClinicalEvidenceSummaries.tsv"
tryLog({
  civic_evidence <- read.table(civic_source, sep="\t", header=T, fill = T, quote = "", comment.char = "%") %>%
    dplyr::rename(chr=chromosome, alt=variant_bases, ref=reference_bases) %>%
    dplyr::mutate(gene = as.character(gene),
                  chr = as.character (chr),
                  start = as.integer(start),
                  stop = as.integer(stop),
                  ref = as.character(ref),
                  alt = as.character(alt)) %>%
    filter(evidence_status == "accepted") %>%
    filter(variant_origin == "Somatic Mutation") %>%
    filter(evidence_type == "Predictive" & evidence_direction == "Supports")
})

if(is.null(civic_evidence) || nrow(civic_evidence)==0){
  log4r::level(logger) <- 'ERROR'
  log4r::error(logger, "CIViC nightly clinical evidence summaries could not be retrieved. Check the download link.")
} else { 
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "CIViC nightly clinical evidence summaries download is successful.")
}

###################
#
# annotate VCF file
#
###################
tryLog({
  vcf <- VariantAnnotation::readVcf(vcfFile, opt$genome) # hg19 = GRCh37
})

if(!exists('vcf')){
  log4r::level(logger) <- "ERROR"
  no_vcf_mesage <- paste(vcfFile, "could not be read in. Check VariantAnnotation package.")
  log4r::error(logger, no_vcf_mesage)
  stop("The VCF file could not be read in. Check VariantAnnotation package.")
}

info <- rownames(VariantAnnotation::info(VariantAnnotation::header(vcf)))
if (!("CSQ" %in% info)) {
  log4r::level(logger) <- "ERROR"
  messages <- paste(vcfFile, "is not annotated.")
  log4r::error(logger, messages)
  log4r::error(logger, "Terminated.")
  stop("Please run VEP on this VCF before generating a report.")
} else {
  messages <- paste(vcfFile, "is annotated. No need to run VEP.")
  log4r::level(logger) <- "INFO"
  log4r::info(logger, messages)
}

header <- stringr::str_sub(VariantAnnotation::info(VariantAnnotation::header(vcf))["CSQ",3], 51)
fields <- stringr::str_split(header, "\\|")[[1]]

ann <- dplyr::tbl_df(VariantAnnotation::info(vcf)) %>%
  dplyr::select(CSQ)
fixed <- VariantAnnotation::fixed(vcf)
ranges <- SummarizedExperiment::rowRanges(vcf)
location <- tbl_df(data.frame(chr = SummarizedExperiment::seqnames(ranges), SummarizedExperiment::ranges(ranges))) %>%
  dplyr::rename(location = names)
fixed$ALT <- unlist(lapply(fixed$ALT, toString))

# minium variant level data (MVLD) according to
# Ritter et al. (https://genomemedicine.biomedcentral.com/articles/10.1186/s13073-016-0367-z)
vep_table <- location %>%
  bind_cols(tbl_df(fixed)) %>%
  bind_cols(ann) %>%
  mutate(chr = stringr::str_extract(chr, "[0-9,X,Y]+")) %>%
  # select only fixed VCF columns plus VEP annotations!
  dplyr::select(chr, start, stop = end, width, location, ref = REF, alt = ALT, qual = QUAL, filter = FILTER, CSQ) %>%
  tidyr::unnest(CSQ) %>%
  tidyr::separate("CSQ", fields, sep = "\\|") %>%
  mutate(Consequence = stringr::str_replace_all(stringr::str_extract(Consequence, "^(?:(?!_variant)\\w)*"), "_", " "),
         #       reference_build = "GRCh37",
         hgnc_id = as.integer(HGNC_ID),
         dbSNP = stringr::str_extract_all(Existing_variation, "rs\\w+"),
         COSMIC = stringr::str_extract_all(Existing_variation, "COSM\\w+"),
         DNA = stringr::str_extract(HGVSc, "(?<=:).*"),
         Protein = stringr::str_extract(HGVSp, "(?<=:).*")) %>% # positive lookbehind
  dplyr::select(-Gene, -HGNC_ID) %>%       # drop Ensembl Gene ID as we're using HUGO from here on
  dplyr::rename(gene_symbol = SYMBOL, Type = VARIANT_CLASS) %>%
  dplyr::mutate(Mutation = ifelse(Consequence == "stop gained", Consequence, Protein)) %>%
  filter(filter == "PASS" | filter == ".") %>% # filter quality
  filter(PICK == 1) # filter only transcripts that VEP picked

if (nrow(vep_table) == 0) {
  log4r::level(logger) <- "ERROR"
  log4r::error(logger, "No variants found that passed the QC tests.")
  log4r::error(logger, "Terminated.")
  stop("No variants found that passed the QC tests.")
} else {
  log4r::level(logger) <- "INFO"
  log4r::info(logger, "MVLD is not empty.")
}

mvld_high_moderate <- vep_table %>%
  filter(IMPACT == "HIGH" | IMPACT == "MODERATE") %>%
  filter(!((SIFT=="tolerated" & PolyPhen=="benign") | (SIFT=="tolerated_low_confidence" & PolyPhen=="benign")))


mvld_modifier_impact <- vep_table %>%
  filter(IMPACT == "MODIFIER")


# now query our annotation database for information on drugs and driver status for all genes occuring in the
# mvld. Then create a relational schema for each with hgnc_id as our 'key', resulting in 3 tables, one each for genes, drivers, and drugs.

if (is.null(opt$database)){
     db_baseurl = 'http://localhost:5000/biograph_genes?where={"hgnc_id":{"$in":["'
     querystring = URLencode(paste(db_baseurl, paste(unique(mvld_high_moderate$hgnc_id), collapse = '","'), '"]}}', sep=''))
     biograph_json <- as.tbl_json(getURL(querystring))
 } else {
     db_result <- jsonlite::fromJSON(dataFile) %>%
       dplyr::mutate(hgnc_id = as.integer(hgnc_id)) %>%
       dplyr::semi_join(mvld_high_moderate, by = c("hgnc_id"))
     db_res <- jsonlite::toJSON(db_result , dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
     biograph_json <- paste0("{","\n", '"_items":', db_res,"\n",'}')
 }

# get information on genes by hgnc_id
biograph_genes <- biograph_json %>%
  tidyjson::enter_object("_items") %>% gather_array() %>%
  spread_values(
    gene_symbol = jstring("gene_symbol"),
    status = jstring("status"),
    hgnc_id = jstring("hgnc_id"),
    driver_score = jnumber("driver_score")
  ) %>%
  mutate(hgnc_id = as.integer(hgnc_id)) %>%
  mutate(driver_score = ifelse(is.na(driver_score), 0, driver_score)) %>%
  dplyr::select(gene_symbol, hgnc_id, status, driver_score)


unnest_cond <- function (df,column_name){
  if (nrow(df) > 0){
    df %>% unnest_(column_name) 
  }
  else {
    df %>% unnest_(column_name, .preserve = column_name)
  }
}

biograph_drugs <- biograph_json %>%
  enter_object("_items") %>% gather_array() %>%
  spread_values(
    gene_symbol = jstring("gene_symbol"),
    hgnc_id = jstring("hgnc_id")
  ) %>%
  dplyr::select(-array.index) %>%
  enter_object("drugs") %>% gather_array() %>%
  spread_values(
    ATC_code = jstring("ATC_code"),
    drug_name = jstring("drug_name"),
    drug_source_name = jstring("source_name"),
    drugbank_id = jstring("drugbank_id"),
    target_action = jstring("target_action"),
    drug_pmid = jstring("pmid"),
    interaction_type = jstring("interaction_type"),
    is_cancer_drug = jlogical("is_cancer_drug"),
    approval_status = jstring("approval_status")
  ) %>%
  mutate(hgnc_id = as.integer(hgnc_id)) %>%
  mutate(drug_pmid = ifelse(drug_pmid == "null", NA, drug_pmid)) %>%
  # make a row for every pubmed id
  mutate(drug_pmid = str_split(drug_pmid, "\\|")) %>%
  as_tibble() %>% unnest_cond("drug_pmid") %>%
  dplyr::select(-document.id, -array.index)

biograph_driver <- biograph_json %>%
  enter_object("_items") %>% gather_array() %>%
  spread_values(
    gene_symbol = jstring("gene_symbol"),
    hgnc_id = jstring("hgnc_id")
  ) %>%
  dplyr::select(-array.index) %>%
  enter_object("cancer") %>% gather_array() %>%
  spread_values(
    driver_type = jstring("driver_type"),
    driver_source_name = jstring("source_name"),
    driver_pmid = jstring("pmid")
  ) %>%
  mutate(hgnc_id = as.integer(hgnc_id)) %>%
  left_join(mvld_high_moderate, by = c("gene_symbol", "hgnc_id")) %>%
  dplyr::select(gene_symbol, Mutation, driver_pmid, driver_type)

# prepare a tidy dataset, where all information on drugs and drivers is available for all mutations, i.e.
# every row is a unique combination of mutation, transcript, gene, driver status, and drug interactions.
# In addition, we apply some standard filters to pick only high quality and LoF mutations and do some renaming.
# mvld_tidy <- mvld %>%
#   left_join(biograph_genes) %>%
#   left_join(biograph_driver) %>%
#   left_join(biograph_drugs)

# driver genes with mutation (irrespective of being a drug target or not)
lof_driver <- biograph_driver %>%
  dplyr::group_by(gene_symbol, Mutation) %>%
  dplyr::summarize(mutation = unique(Mutation), Confidence = n(), DriverType = paste(driver_type, collapse = "|"), References = paste(driver_pmid, collapse = "|")) %>%
  dplyr::arrange(desc(Confidence)) %>%
  dplyr::mutate(Type = case_when (grepl("TSG", DriverType, fixed=TRUE) & grepl("Oncogene", DriverType) ~ "TSG/Oncogene",
                                  grepl("TSG", DriverType, fixed=TRUE) ~ "TSG",
                                  grepl("Oncogene", DriverType, fixed=TRUE) ~ "Oncogene",
                                  TRUE ~ "unknown")) %>%
  dplyr::select(-Mutation, -DriverType) %>%
  dplyr::rename(Gene = gene_symbol, Mutation = mutation)

# table to get the frequencies of the type variable in the table
count_table <- lof_driver %>%
  dplyr::select(Gene, Type) %>%
  dplyr::distinct(Gene, .keep_all = TRUE)

num_of_snvs = length(unique(mvld_high_moderate$location)) # to get number of SNVs
num_of_oncogenes <- length(which(count_table$Type == "Oncogene")) + length(which(count_table$Type == "TSG/Oncogene"))
num_of_tsg <- length(which(count_table$Type == "TSG")) + length(which(count_table$Type == "TSG/Oncogene"))

# cancer drug targets with mutation

# direct association:
# cancer drug targets with mutation
lof_variant_dt_table <- biograph_drugs %>%
  # only cancer drug targets
  filter(is_cancer_drug & interaction_type == "target") %>%
  dplyr::left_join(mvld_high_moderate, by = c("gene_symbol", "hgnc_id")) %>%
  group_by(gene_symbol, approval_status, drug_name) %>%
  summarise(Confidence = n(), References = paste(unique(na.omit(drug_pmid)), collapse = "|")) %>%
  dplyr::select(Gene = gene_symbol, Status = approval_status, Therapy = drug_name, Confidence, References) %>%
  dplyr::arrange(desc(Confidence))

# indirect associations:
# other mutations in *any* gene (not necessarily drug target) with known effect on drug.
# Here we list all genes with any LoF mutation (not necessarily the same mutation that occured in the sample) with evidence
# that the affected patient could show a resistance to a drug. Note that lof_civic_dt_table is a superset
# of drug_variants below.
lof_civic_dt_table <- mvld_high_moderate %>%
  inner_join(civic_evidence, by = c("gene_symbol" = "gene")) %>%
  dplyr::select(Gene = gene_symbol, Mutation = variant, Therapy = drugs, Disease = disease, Effect = clinical_significance, Evidence = evidence_level, References = pubmed_id)



# mutation-specific annotations (from civic)
# These are mutations reported by CiVIC with a known pharmacogenetic effect, clinical significance, and evidence level.
# Note that these variants have to match with the sample variants in their exact position on the genome.

# Put conditions according to the genome assembly for CIViC DB
if (opt$genome == "GRCh38") {
  civic_evidence_38 = read.table(opt$civic38, sep="\t", header=T, fill = T, quote = "", comment.char = "%") %>%
    dplyr::rename(chr=chromosome, alt=variant_bases, ref=reference_bases) %>%
    dplyr::mutate(gene = as.character(gene),
                  chr = as.character (chr),
                  start = as.integer(start),
                  stop = as.integer(stop),
                  ref = as.character(ref),
                  alt = as.character(alt)) %>%
    filter(evidence_status == "accepted") %>%
    filter(variant_origin == "Somatic Mutation") %>%
    filter(evidence_type == "Predictive" & evidence_direction == "Supports")

  drug_variants <- mvld_high_moderate %>%
    inner_join(civic_evidence_38, by = c("gene_symbol" = "gene", "chr", "start", "stop", "ref", "alt")) %>%
    dplyr::select(Gene = gene_symbol, Mutation = variant, Therapy = drugs, Disease = disease, Effect = clinical_significance, Evidence = evidence_level, References = pubmed_id) %>%
    arrange(Evidence)
} else {
  drug_variants <- mvld_high_moderate %>%
    inner_join(civic_evidence, by = c("gene_symbol" = "gene", "chr", "start", "stop", "ref", "alt")) %>%
    dplyr::select(Gene = gene_symbol, Mutation = variant, Therapy = drugs, Disease = disease, Effect = clinical_significance, Evidence = evidence_level, References = pubmed_id) %>%
    arrange(Evidence)
}

# Now remove drug_variants that are also contained in lof_civic_dt_table
lof_civic_dt_table <- setdiff(lof_civic_dt_table, drug_variants) %>%
  arrange(Evidence)

# check if all the results are empty and terminate if so
if (nrow(lof_driver) == 0 && nrow(lof_variant_dt_table) == 0 && nrow(lof_civic_dt_table) == 0 && nrow(drug_variants) == 0){
  log4r::level(logger) <- "INFO"
  log4r::info(logger, "No information found from databases. Terminating the program.")
  log4r::level(logger) <- "FATAL"
  messages = paste("No results could be found for ", basename(opt$file))
  log4r::fatal(logger,  messages)
  stop(messages)
}

# build a reference index to the bibliography
reference_map <- tibble(References = c(lof_driver$References, lof_variant_dt_table$References, lof_civic_dt_table$References, drug_variants$References)) %>%
  mutate(References = str_split(References, "\\|")) %>%
  unnest(References) %>%
  mutate(References = str_trim(References)) %>%
  distinct() %>%
  tibble::rowid_to_column()

tryLog({
  base_url <- "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?retmode=json;db=pubmed;id="
  querystring <- URLencode(paste(base_url, paste(
    (reference_map$References), collapse = ",", sep = ""), sep = ""))
})

references_json <- as.tbl_json(getURL(querystring))

references <- references_json  %>%
  enter_object("result") %>%
  gather_object() %>%
  spread_values(
    first = jstring("sortfirstauthor"),
    title = jstring("title"),
    journal = jstring("fulljournalname"),
    volume = jstring("volume"),
    issue = jstring("issue"),
    pages = jstring("pages"),
    date = jstring("pubdate")
  ) %>%
  filter(row_number() != 1) %>%
  mutate(
    year = str_extract(date, "\\d*"),
    authors = paste(stringr::str_extract(first, "\\w*"), "et al."),
    citation = paste(authors, title, journal, volume, issue, year, sep = ", ")
  ) %>%
  left_join(reference_map, by = c("name" = "References")) %>%
  dplyr::select(rowid, citation)


if (nrow(references) > 0){
  if (nrow(mvld_high_moderate) > 0) {
    appendix <- mvld_high_moderate %>%
      dplyr::select(Gene = gene_symbol, Mutation, dbSNP, COSMIC)
    log4r::level (logger) <- 'INFO'
    log4r::info (logger, " A non-empty 'appendix' table is created.")
  } else {
    # Set the current level of the logger.
    log4r::level (logger) <- 'WARN'
    log4r::warn(logger, "'Appendix' table is not generated since 'mvld' table is present.")
  }
} else {
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'References' and 'Appendix' tables will not be generated in the report since 'references' table is empty.")
}


# now replace pubmed ids with indexes for all the previous tables

if (nrow(lof_driver)) {
  lof_driver <- lof_driver %>%
    mutate(References = str_split(References, "\\|")) %>%
    unnest(References) %>%
    mutate(References = str_trim(References)) %>%
    left_join(reference_map, by = "References") %>%
    group_by(Gene, Mutation, Confidence, Type) %>%
    arrange(rowid, .by_group = T) %>%
    summarise(References = paste(rowid, collapse = ",")) %>%
    dplyr::arrange(desc(Confidence))
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "A non-empty 'lof_driver' tabel is present.")
} else {
  # Set the current level of the logger.
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'Somatic Mutations in Known Driver Genes' table will not be generated in the report since 'lof_driver' table is empty.")
}

if (nrow(lof_variant_dt_table) == FALSE & nrow(lof_civic_dt_table) == FALSE){
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'Somatic Mutations in Pharmaceutical Target Proteins' table will not be generated in the report since'lof_variant_dt_table' and  'lof_civic_dt_table' are empty.")
} 

if (nrow(lof_variant_dt_table)) {
  lof_variant_dt_table <- lof_variant_dt_table %>%
    mutate(References = str_split(References, "\\|")) %>%
    unnest(References) %>%
    mutate(References = str_trim(References)) %>%
    left_join(reference_map, by = "References") %>%
    group_by(Gene, Status, Therapy, Confidence) %>%
    arrange(rowid, .by_group = T) %>%
    summarise(References = paste(rowid, collapse = ",")) %>%
    dplyr::arrange(desc(Confidence))
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "A non-empty 'lof_variant_dt_table' is present.")
} else {
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'Direct Association (Mutation in Drug Target)' table will not be generated in the report since 'lof_variant_dt_table' is empty.")
}

if (nrow(lof_civic_dt_table)) {
  lof_civic_dt_table <- lof_civic_dt_table %>%
    mutate(References = str_split(References, "\\|")) %>%
    unnest(References) %>%
    mutate(References = str_trim(References)) %>%
    left_join(reference_map, by = "References") %>%
    group_by(Gene, Mutation, Therapy, Effect, Disease, Evidence) %>%
    summarise(References = paste(rowid, collapse = ",")) %>%
    arrange(Evidence)
  # If user provided a metadata with diagnosis information, create another version of lof_civic_dt_table by filtering for the diagnosis
  if (exists('patient_diagnosis_short') && !is.null(patient_info$patient_diagnosis_short)){
    lof_civic_dt_table <- lof_civic_dt_table %>%
    dplyr::filter(Disease == patient_info$patient_diagnosis_short | Disease == "Cancer")
  }
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "A non-empty 'lof_civic_dt_table' is present.")
} else {
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'Indirect Association (Other Mutations with Known Effect on Drug)' table will not be generated in the report since 'lof_civic_dt_table' is empty.")
}

if (nrow(drug_variants)) {
  drug_variants <- drug_variants %>%
    mutate(References = str_split(References, "\\|")) %>%
    unnest(References) %>%
    mutate(References = str_trim(References)) %>%
    left_join(reference_map, by = "References") %>%
    group_by(Gene, Mutation, Therapy, Effect, Disease, Evidence) %>%
    summarise(References = paste(rowid, collapse = ",")) %>%
    arrange(Evidence)
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, "A non-empty 'drug_variants' is present.")
} else {
  log4r::level(logger) <- 'WARN'
  log4r::warn(logger, "'Somatic Mutations with Known Pharmacogenetic Effect' table will not be generated in the report since 'drug_variants' is empty. ")
}


########################### Converting dataframes to json format (only applied to tables that are printed in report).
# Create an empty json object of patient data 
# patient_info <- list(patient_firstname = "", patient_lastname = "", patient_dateofbirth = "", patient_diagnosis_short="", mutation_load="", mutation_ns_snv="", mutation_affected_oncogenes="", mutation_affected_tumorsupressorgenes="", mutation_hla_type="", mutation_additional_information="" )
# patient_info_json <- jsonlite::toJSON(patient_info, prety = TRUE, auto_unbox = TRUE)
#patient_info <- jsonlite::toJSON(jsonlite::fromJSON("metadata.json"), dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE, auto_unbox = TRUE)

if (is.null(opt$metadata)) {
  patient_info_table <- paste0('"patient_firstname"',":",'"",',
                         "\n",'"patient_lastname"',":",'"",',
                         "\n",'"patient_dateofbirth"',":", '"",',
                         "\n",'"patient_diagnosis_short"',":", '"",',
                         "\n",'"mutation_load"',":", '"",',
                         "\n",'"mutation_ns_snv"',":", '"', num_of_snvs, '",',
                         "\n",'"mutation_affected_oncogenes"',":", '"', num_of_oncogenes, '",',
                         "\n",'"mutation_affected_tumorsupressorgenes"',":", '"', num_of_tsg, '",',
                         "\n",'"mutation_additional_information"',":",'""')
} else {
  # mimic the structure
  patient_info_table <- paste0('"patient_firstname"',":",'"', patient_info$patient_firstname, '",', 
                               "\n",'"patient_lastname"',":",'"', patient_info$patient_lastname, '",',
                               "\n",'"patient_dateofbirth"',":", '"', patient_info$patient_dateofbirth, '",',
                               "\n",'"patient_diagnosis_short"',":", '"', patient_info$patient_diagnosis_short, '",',
                               "\n",'"mutation_load"',":", '"', patient_info$mutation_load, '",',
                               "\n",'"mutation_ns_snv"',":", '"', num_of_snvs, '",',
                               "\n",'"mutation_affected_oncogenes"',":", '"', num_of_oncogenes, '",',
                               "\n",'"mutation_affected_tumorsupressorgenes"',":", '"', num_of_tsg, '",',
                               "\n",'"mutation_additional_information"',":",'""')
}


lof_driver_json <- jsonlite::toJSON(lof_driver , dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
lof_variant_dt_table_direct_json <- jsonlite::toJSON(lof_variant_dt_table , dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
lof_civic_dt_table_indirect_json <- jsonlite::toJSON(lof_civic_dt_table, dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
drug_variants_json <- jsonlite::toJSON(drug_variants, dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
references_table_json <- jsonlite::toJSON(references, dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)
appendix_table_json <- jsonlite::toJSON(appendix, dataframe = c("rows"), matrix = c("columnmajor"), pretty = TRUE)

# Merge tables into one 'report' json.
report <- paste0("{","\n", patient_info_table, ',',"\n", '"mskdg":',lof_driver_json,',',"\n", '"ptp_da":',lof_variant_dt_table_direct_json,',',"\n",'"ptp_ia":',lof_civic_dt_table_indirect_json, ',',"\n", '"mskpe":',drug_variants_json,',',"\n",'"ref":',references_table_json,',',"\n",'"appendix":',appendix_table_json ,"\n",'}')
writeLines(report, reportFile)
if(file.exists(reportFile)) {
  message <- paste(reportFile, "is saved.")
  log4r::level(logger) <- 'INFO'
  log4r::info(logger, message)
} else {
  log4r::level(logger) <- 'ERROR'
  log4r::error(logger, "JSON output is not created.") 
}