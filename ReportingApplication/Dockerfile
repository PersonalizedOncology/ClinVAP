FROM ensemblorg/ensembl-vep:release_93

LABEL maintainer="sueruen@informatik.uni-tuebingen.de"

# update vep, install and configure required vep plugins
USER vep
WORKDIR $OPT/src/ensembl-vep
RUN git pull && \
  git checkout release/93 && \
  ./INSTALL.pl -n -a p -g LoFtool

USER root
# install current version of R and required packages for vep
RUN sh -c 'echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/" >> /etc/apt/sources.list' && \
  sh -c 'echo "deb http://ftp.halifax.rwth-aachen.de/ubuntu xenial-backports main restricted universe" >> /etc/apt/sources.list' && \
  gpg --keyserver keyserver.ubuntu.com --recv-key E084DAB9 && \
  gpg -a --export E084DAB9 | apt-key add -

RUN apt-get -y update && \
  apt-get install -y --allow-unauthenticated r-base libxml2-dev libcurl4-openssl-dev libssh2-1-dev libcairo2-dev samtools libpq-dev nodejs npm libreoffice
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# install R packages
RUN Rscript -e 'install.packages(c("dplyr", "dtplyr", "stringr","splitstackshape", "optparse", "readr", "RCurl", "devtools", "log4r", "futile.logger", "fs"), dependencies = TRUE, repos = "https://cloud.r-project.org")'
RUN Rscript -e 'devtools::install_github("colearendt/tidyjson@d79f3ff0a3279adef07819af4ab572f9ba46f3c0")'
RUN Rscript -e 'devtools::install_github("aryoda/tryCatchLog@aa115fe2bd7b6569492eb0a9673f028ee6ec40a2")'
RUN Rscript -e 'source("https://bioconductor.org/biocLite.R"); biocLite(c("VariantAnnotation", "rjson"), ask = FALSE, suppressUpdates = TRUE)'
RUN Rscript -e 'devtools::install_version("tidyr", version = "0.8.3")'

# Although LoF is installed via VEP's install script above, it's unclear which version.
# To be sure, we overwrite it with the latest release on github
WORKDIR /opt/vep
USER vep
RUN wget https://github.com/konradjk/loftee/archive/v0.3-beta.zip && \
  unzip v0.3-beta.zip && \
  rm v0.3-beta.zip && \
  cp loftee-0.3-beta/LoF.pm /opt/vep/.vep/Plugins

USER root
# this is required for loftee-0.3-beta
RUN cpanm DBD::SQLite
ENV PERL5LIB /opt/vep/loftee-0.3-beta/:$PERL5LIB

# copy configuration files
COPY vep_docker.ini /opt/vep/.vep/vep.ini
COPY make_report.sh /opt/vep/
COPY reporting.R /opt/vep
COPY driver_db_dump.json /opt/vep
RUN mkdir clinicalreporting_docxtemplater
COPY clinicalreporting_docxtemplater /opt/vep/clinicalreporting_docxtemplater
COPY GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt /opt/vep/GRCh38_01-Jan-2019-ClinicalEvidenceSummaries.txt

WORKDIR /opt/vep/clinicalreporting_docxtemplater
RUN npm install

WORKDIR /opt/vep
#RUN chmod +x /home/vep/make_report.sh /home/vep/reporting.R
#CMD /home/vep/make_report.sh
RUN touch docker.flag && \ 
 echo "This file is created to signal make report script that docker is using it. It means database dump is not given as a parameter.  " >> docker.flag

RUN chmod +x make_report.sh reporting.R
ENTRYPOINT ["/opt/vep/make_report.sh"]
