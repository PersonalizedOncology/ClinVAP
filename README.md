![Pipeline Logo](https://github.com/sbilge/ClinVAP/blob/master/doc/logo.jpeg)

[![Release: Github](https://img.shields.io/github/release/PersonalizedOncology/ClinicalReportingPipeline.svg)](https://github.com/PersonalizedOncology/ClinVAP/releases)
[![https://www.singularity-hub.org/static/img/hosted-singularity--hub-%23e32929.svg](https://www.singularity-hub.org/static/img/hosted-singularity--hub-%23e32929.svg)](https://singularity-hub.org/collections/2168)
[![Docker: Available](https://img.shields.io/badge/hosted-docker--hub-blue.svg)](https://cloud.docker.com/u/personalizedoncology/repository/list)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)  

# Clinical Variant Annotation Pipeline

Clinical Variant Annotation Pipeline (ClinVAP) creates a genetic report of somatic mutations from a variant call format (VCF) file. Please refer this document for implementation of the pipeline. Documentation of the pipeline is available at [Wiki page](https://github.com/PersonalizedOncology/ClinVAP/wiki). 

### Metadata Structure
If a patient metadata file is provided in the input directory with the naming schema \<INPUT\_VCF\_NAME\>\_metadata.json, ClinVAP recognizes it and renders the information into the Patient Data table in the outputted report. Additionally, if dignosis is provided in the metadata file, the list of drugs with the clinical evidence of targeting the gene in that particular cancer type is reported in the "CIViC Summary of Drugs Targeting the Affected Genes" table. If no diagnosis is provided, then the pipeline stays agnostic to the cancer type, and returns the results related with the gene-drug association regardless of the cancer type. Please note that the disease name should be selected from the pre-defined dictionary that can be found [here](https://github.com/PersonalizedOncology/ClinVAP/blob/master/doc/disease_names_dictionary.txt).   

**Metadata file format:**  
\{  
"patient\_firstname":"\<NAME\>",  
"patient\_lastname":"\<SURNAME\>",  
"patient\_dateofbirth":"\<DATE\>",  
"patient\_diagnosis\_short":"\<DIAGNOSIS\>",  
"mutation\_load":"\<LOAD\>"  
\}  


## Usage with Singularity

Requirements: Singularity 2.4+  
Please make sure that you have 12 GB of empty space on your home directory, and ports 5000 and 27021 are not being used by another application.
To run the pipeline, please follow the steps given below. 

1. Pull reporting image from Singularity Hub.
 `singularity pull -n reporting_app.img  shub://PersonalizedOncology/ClinVAP:report` 
2. Pull dependency files image from Singularity Hub. 
`singularity pull -n file_deploy.img  shub://PersonalizedOncology/ClinVAP:filedeploy`
3. Run dependency files image first to transfer those file on your local folder. 
 `singularity run -B /LOCAL/PATH/TO/FILES:/mnt file_deploy.img -a <Your Assembly Here>`
4. Run the reporting image to generate the clinical reports. 
`singularity run -B /LOCAL/PATH/TO/FILES:/data -B /PATH/TO/INPUT/DATA:/inout reporting_app.img -t /inout -p jwp -a <Your Assembly Here>`


* `-a`: Please provide the genome assembly that was used in variant calling calling step to generate your VCF files. 
	* `GRCh37` for genome assembly 37 
	* `GRCh38` for genome assembly 38

* `-t`: folder name containing input data. This should be in the data volume of ClinicalReportR service (modify Docker compose file to change this).
* `-p`: output format to save the results.
	* `j` to save report in JSON format
	* `w` to save report in DOCX format
	* `p` to save report in PDF format

You should now have the report in your /PATH/TO/INPUT/DATA folder.

## Usage with Docker

### For Mac and Ubuntu Users

Requirements: Docker Engine release 1.13.0+, Compose release 1.10.0+.  
Please make sure that you have 34 GB of physical empty space on your Docker Disk Image, and ports 5000 and 27017 are not being used by another application.

To tun the pipeline, please follow the steps given below. 

```
1. git clone https://github.com/PersonalizedOncology/ClinVAP.git
```
Pelase note that the input VCF file(s) should be in ReportingApplication/inout folder.

```
2. cd ClinVAP/
3. export ASSEMBLY=<Your Assembly Here>
4. docker-compose run -e ASSEMBLY --service-ports ClinicalReportR -t /inout -p jwp -a <Your Assembly Here>

```
* `<Your Assembly Here>`: Please provide the genome assembly that was used in variant calling calling step to generate your VCF files. 
	* `GRCh37` for genome assembly 37 
	* `GRCh38` for genome assembly 38
* `-t`: folder name containing input data. This should be in the data volume of ClinicalReportR service (modify Docker compose file to change this).
* `-p`: output format to save the results.
	* `j` to save report in JSON format
	* `w` to save report in DOCX format
	* `p` to save report in PDF format

You should now have the report in ReportingApplication/inout folder.

### Running with Docker Toolbox For Windows Users 

Requirements: Docker Engine release 1.13.0+, Compose release 1.10.0+.  
Please make sure that you have 34 GB of physical empty space on your Docker Disk Image, and ports 5000 and 27017 are not being used by another application.

To tun the pipeline, please follow the steps given below. 

```
1. git clone https://github.com/PersonalizedOncology/ClinVAP.git
```
Pelase note that the input VCF file(s) should be in ReportingApplication/inout folder.

```
2. cd ClinVAP/
3. export ASSEMBLY=<Your Assembly Here>
4. docker-compose run -e ASSEMBLY --service-ports ClinicalReportR -t //inout -p jwp -a <Your Assembly Here>

```
* `<Your Assembly Here>`: Please provide the genome assembly that was used in variant calling calling step to generate your VCF files. 
	* `GRCh37` for genome assembly 37 
	* `GRCh38` for genome assembly 38
* `-t`: folder name containing input data. This should be in the data volume of ClinicalReportR service (modify Docker compose file to change this).
* `-p`: output format to save the results.
	* `j` to save report in JSON format
	* `w` to save report in DOCX format
	* `p` to save report in PDF format

You should now have the report in ReportingApplication/inout folder.

## Demo Run
We provided an example input file, strelka\_passed\_missense\_somatic\_snvs.vcf under ./ReportingApplication/inout folder along with a dummy metadata file, strelka\_passed\_missense\_somatic\_snvs.json. The corresponding report of the strelka input file is provided [here](https://github.com/PersonalizedOncology/ClinVAP/tree/master/doc/strelka_passed_missense_somatic_snvs.pdf) as an example. 

### Running Demo with Singularity
```
1. git clone https://github.com/PersonalizedOncology/ClinVAP.git
2. singularity pull -n reporting_app.img  shub://PersonalizedOncology/ClinVAP:report
3. singularity pull -n file_deploy.img  shub://PersonalizedOncology/ClinVAP:filedeploy
4. mkdir vep_files
5. singularity run -B ./vep_files:/mnt file_deploy.img -a GRCh37
6. singularity run -B ./vep_files:/data -B ./ClinVAP/ReportingApplication/inout:/inout reporting_app.img -t /inout -p jwp -a GRCh37

```
### Running Demo with Docker

```
1. git clone https://github.com/PersonalizedOncology/ClinVAP.git
2. cd ClinVAP/
3. export ASSEMBLY=GRCh37
4. docker-compose run -e ASSEMBLY --service-ports ClinicalReportR -t /inout -p jwp -a GRCh37

```
### Citation

If you use ClinVAP in your work, please cite the following article

* Sürün, B., Schärfe, C.P., Divine, M.R., Heinrich, J., Toussaint, N.C., Zimmermann, L., Beha, J. and Kohlbacher, O., 2020. ClinVAP: a reporting strategy from variants to therapeutic options. Bioinformatics, 36(7), pp.2316-2317.
