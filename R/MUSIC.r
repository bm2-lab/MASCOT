#################################       Data Preprocessing     ############################
# ********************** data importing
# if data format is 10X, for convenience, this function is better.
Input_preprocess_10X<-function(directory){
  require(hash)
  require(stringr)
  perturb_seq <- Read10X(directory)
  perturb_seq <- as.matrix(perturb_seq)
  cbc_gbc <- read.table(paste(directory, "cbc_gbc_dict.tsv",sep = "/"), stringsAsFactors = FALSE)
  cbc_gbc <- unique(cbc_gbc)
  data_preprocess <- function(perturb_seq, cbc_gbc) {
    cell_KO_hash = hash()
    for (i in 1:nrow(cbc_gbc)) {
      cbc = cbc_gbc[i, 1]
      gbc = cbc_gbc[i, 2]
      if (has.key(cbc, cell_KO_hash)) {
        cell_KO_hash[cbc] = paste(cell_KO_hash[[cbc]],gbc, sep = ",")
      }
      else {
        cell_KO_hash[cbc] = gbc
      }
    }
    perturb_information = c()
    j = 1
    k = 1
    nogbc_col = c()
    for (i in 1:ncol(perturb_seq)) {
      if (!is.null(cell_KO_hash[[colnames(perturb_seq)[i]]])) {
        perturb_information[k] = cell_KO_hash[[colnames(perturb_seq)[i]]]
        k = k + 1
      }
      else {
        nogbc_col[j] <- i
        j = j + 1
      }
    }
    perturb_seq <- perturb_seq[, -nogbc_col]
    names(perturb_information) = colnames(perturb_seq)
    for (i in 1:length(perturb_information)) {
      sample_info_arr <- unlist(strsplit(perturb_information[i],","))
      if (length(sample_info_arr) > 1) {
        sortedMultiKO<-c()
        sample_info_arr <- sort(sample_info_arr)
        if(sample_info_arr[1]!="CTRL"){
          sortedMultiKO=sample_info_arr[1]
          for (j in 2:length(sample_info_arr)) {
            if(sample_info_arr[j]!="CTRL"){
              sortedMultiKO = paste(sortedMultiKO, sample_info_arr[j],sep = ",")
            }
          }
        }
        else{
          sortedMultiKO=sample_info_arr[2]
          if(length(sample_info_arr)>=3){
            for (j in 3:length(sample_info_arr)) {
              if(sample_info_arr[j]!="CTRL"){
                sortedMultiKO = paste(sortedMultiKO, sample_info_arr[j],sep = ",")
              }
            }
          }
        }
        perturb_information[i] = sortedMultiKO
      }
    }
    perturb_seq <- perturb_seq[!str_detect(row.names(perturb_seq),"^MRP"), ]
    perturb_seq <- perturb_seq[!str_detect(row.names(perturb_seq),"^RP"), ]
    return(list("perturb_data" = perturb_seq, "perturb_information" = perturb_information))
  }
  perturb_seq_list <- data_preprocess(perturb_seq, cbc_gbc)
  perturb_list = list("expression_profile" = perturb_seq_list$perturb_data, "perturb_information" = perturb_seq_list$perturb_information)
  return(perturb_list)
}
# no matter what the original data format is, users can handle the original data to this format.
Input_preprocess<-function(expression_profile,perturb_information){
  require(stringr)
  options(warn=1)
  if(ncol(expression_profile)!=length(perturb_information)){
    warning("expression_profile and perturb_information have different length, please check and try again.")
  }
  for (i in 1:length(perturb_information)) {
    sample_info_arr <- unlist(strsplit(perturb_information[i],","))
    if (length(sample_info_arr) > 1) {
      sortedMultiKO<-c()
      sample_info_arr <- sort(sample_info_arr)
      if(sample_info_arr[1]!="CTRL"){
        sortedMultiKO=sample_info_arr[1]
        for (j in 2:length(sample_info_arr)) {
          if(sample_info_arr[j]!="CTRL"){
            sortedMultiKO = paste(sortedMultiKO, sample_info_arr[j],sep = ",")
          }
        }
      }
      else{
        sortedMultiKO=sample_info_arr[2]
        if(length(sample_info_arr)>=3){
          for (j in 3:length(sample_info_arr)) {
            if(sample_info_arr[j]!="CTRL"){
              sortedMultiKO = paste(sortedMultiKO, sample_info_arr[j],sep = ",")
            }
          }
        }
      }
      perturb_information[i] = sortedMultiKO
    }
  }
  expression_profile<-expression_profile[(!str_detect(row.names(expression_profile),"^MRP")) & (!str_detect(row.names(expression_profile),"^RP")),]#filter mitochondrial ribosomal protein and ribosomal protein
  return(list("expression_profile"=expression_profile,"perturb_information"=perturb_information))
}
# ********************** quality control of data
Cell_qc<-function(expression_profile,perturb_information,species="Hs",gene_low=500,gene_high=10000,mito_high=0.1,umi_low=1000,umi_high=Inf,plot=FALSE,plot_path="./quality_control.pdf"){
  require(stringr)
  if(species=="Hs"){
    mito.genes <- grep("^MT-", rownames(expression_profile), value = FALSE)
  }else if(species=="Mm"){
    mito.genes <- grep("^mt-", rownames(expression_profile), value = FALSE)
  }else{
    stop("species should be 'Mm' or 'Hs'")
  }
  mito_percent<-function(x,mito.genes){
    return(sum(x[mito.genes])/sum(x))
  }    
  percent.mito<-apply(expression_profile,2,mito_percent,mito.genes=mito.genes)
  nUMI<-apply(expression_profile,2,sum)
  nGene<-apply(expression_profile,2,function(x){length(x[x>0])})
  expression_profile<-apply(expression_profile,2,function(x){x/(sum(x)/10000)})
  expression_profile<-log(expression_profile+1)    
  if(species=="Hs"){
    expression_profile<-expression_profile[!str_detect(row.names(expression_profile),"^MT-"),]
  }else if(species=="Mm"){
    expression_profile<-expression_profile[!str_detect(row.names(expression_profile),"^mt-"),]
  }
  filter_retain<-rep("filter",ncol(expression_profile))
  for(i in 1:length(filter_retain)){
    if(nGene[i]>gene_low & nGene[i]<gene_high & percent.mito[i]<mito_high & nUMI[i]>umi_low & nUMI[i]<umi_high){
      filter_retain[i]<-"retain"
    }
  }
  if(plot){
    pdf(file=plot_path)
    par(mfrow=c(1,3))
    hist(nGene,breaks = 20,freq=FALSE,xlab = "Gene numbers",ylab = "Density",main = "Gene numbers distribution")
    lines(nGene,col="red",lwd=1)
    hist(nUMI,breaks = 20,freq=FALSE,xlab = "UMI numbers",ylab = "Density",main = "UMI numbers distribution")
    lines(density(nUMI),col="red",lwd=1)
    hist(percent.mito,breaks = 20,freq=FALSE,xlab = "Percent of mito",ylab = "Density",main = "Percent of mito distribution")
    lines(density(percent.mito),col="red",lwd=1)
    dev.off()
  }
  SQ_filter<-as.matrix(expression_profile[,which(filter_retain=="retain")])
  SQ_data_qc<-SQ_filter#have adopted total_expr=10000 and log
    perturb_information_qc<-perturb_information[colnames(SQ_data_qc)]
    perturb_information_abandon<-perturb_information[setdiff(names(perturb_information),names(perturb_information_qc))]
    return(list("expression_profile"=SQ_data_qc,"perturb_information"=perturb_information_qc,"perturb_information_abandon"=perturb_information_abandon))
}

#*********************** complementary expression profile with SAVER package
Data_imputation<-function(expression_profile,perturb_information,cpu_num=4,split=2){
  require(doParallel)
  require(SAVER)
  gene_num<-nrow(expression_profile)
  cl <- makeCluster(cpu_num, outfile = "")
  registerDoParallel(cl)
  saver_list<-list()
  for(i in 1:split){
    print(paste("Genes were splited with",split,"parts","now it is calculating",i,sep=" "))
    saver_list[[i]]<-saver(expression_profile, pred.genes = (floor(gene_num*(i-1)/split)+1):floor(gene_num*i/split), pred.genes.only = TRUE,size.factor=1)
  }
  expression_profile_saver <- combine.saver(saver_list)
  expression_profile<-expression_profile_saver$estimate
  stopCluster(cl)
  return(list("expression_profile"=expression_profile,"perturb_information"=perturb_information))
}
# ********************   replace official gene names
perturb_information_replace_name<-function(perturb_information,original_name,replace_name){
  require(stringr)
  original_name_f<-paste(",",original_name,sep="")
  original_name_b<-paste(original_name,",",sep="")
  replace_name_f<-paste(",",replace_name,sep="")
  replace_name_b<-paste(replace_name,",",sep="")
  perturb_information[perturb_information==original_name]<-replace_name
  for(i in 1:length(perturb_information)){
    if(str_detect(perturb_information[i],original_name_b)){
      perturb_information[i]<-sub(original_name_b,replace_name_b,perturb_information[i])
    }
    if(str_detect(perturb_information[i],original_name_f)){
      perturb_information[i]<-sub(original_name_f,replace_name_f,perturb_information[i])
    }
  }
  return(perturb_information)
}
# ******************** parallel calculation for cosin similarity for two matrix
cosin_dis_diffMatrix<-function(matrix1,matrix2,cpu_num){
  library(parallel)
  matrix1<-matrix1+0.01
  matrix2<-matrix2+0.01
  cos_matrix<-matrix(rep(1,nrow(matrix1)*nrow(matrix2)),nrow(matrix1))
  colnames(cos_matrix)<-row.names(matrix2)
  row.names(cos_matrix)<-row.names(matrix1)
  cos_d<-function(vec1,vec2){
    cos_result<-sum(vec1*vec2)/sqrt(sum(vec1^2)*sum(vec2^2))
    return(cos_result)
  }
  simi_cos<-function(vec,matrix){
    cor_m<-apply(matrix,1,cos_d,vec2=vec)
    return(cor_m)
  }
  if(cpu_num>1){
    cpu_num_set <- makeCluster(cpu_num)
    cos_matrix<-parApply(cpu_num_set,matrix1,1,simi_cos,matrix=matrix2)
    stopCluster(cpu_num_set)
    return(cos_matrix)
  }else{
    cos_matrix<-apply(matrix1,1,simi_cos,matrix=matrix2)
    return(cos_matrix)
  }
}
#*********************** cell filtering for low sgRNA efficiency
Cell_filtering<-function(expression_profile,perturb_information,cpu_num=4,cell_num_threshold=30,umi=0.01,pvalue=0.05,vargene_min_num=5,filtered_rate=0.9,plot=FALSE,plot_path="./invalid_rate.pdf"){
  library(parallel)
  library(stringr)
  options(warn=-1)
  get_varGene<-function(ex,s){
    a=ks.test(as.numeric(ex[1:s]),as.numeric(ex[(s+1):length(ex)]))
    return(as.numeric(a$p.value))
  }
  perturb_information_delete_name<-function(perturb_information,delete_name){
    require(stringr)
    if(delete_name=="*"){
      perturb_information<-perturb_information[perturb_information!="*"]
      return(perturb_information)
    }
    delete_name_f<-paste(",",delete_name,sep="")
    delete_name_b<-paste(delete_name,",",sep="")
    perturb_information[perturb_information==delete_name]<-"wait_delete"
    for(i in 1:length(perturb_information)){
      if(str_detect(perturb_information[i],delete_name_b)){
        perturb_information[i]<-sub(delete_name_b,"",perturb_information[i])
      }
      if(str_detect(perturb_information[i],delete_name_f)){
        perturb_information[i]<-sub(delete_name_f,"",perturb_information[i])
      }
    }
    perturb_information<-perturb_information[perturb_information!="wait_delete"]
    return(perturb_information)
  }
  perturb_information_ko<-perturb_information[perturb_information!="CTRL"]
  perturb_information_ko_split<-c()
  for(i in 1:length(perturb_information_ko)){
    ko_split<-unlist(str_split(perturb_information_ko[i],","))
    names(ko_split)<-rep(names(perturb_information_ko)[i],length(ko_split))
    perturb_information_ko_split<-c(perturb_information_ko_split,ko_split)
  }
  #filter KO genes who express little in ctrl samples, because it makes no sense.
  #calculate percent of zero value of control sample
  ko_names<-unique(perturb_information_ko_split)
  Zero_ra<-c()
  if(length(ko_names[!(ko_names %in% row.names(expression_profile))])>0){
    print(paste("Warning! ",ko_names[!(ko_names %in% row.names(expression_profile))],"can't be found in the expression profile, the names of this knockout or knockdown maybe not official gene name, please check and use official gene name instead. Then run this function again. If it is already official gene name, then just go on!"))
  }
  for(i in 1:length(ko_names)){
    if(ko_names[i] %in% row.names(expression_profile)){
      zero_ratio<-length(expression_profile[ko_names[i],][which(expression_profile[ko_names[i],]==0)])/ncol(expression_profile)
      Zero_ra[i]<-zero_ratio
      if(zero_ratio==1){
        print(paste(ko_names[i],"doesn't express and will be filtered.",sep=" "))
        perturb_information_ko<-perturb_information_delete_name(perturb_information_ko,ko_names[i])
      }
    }else{
      Zero_ra[i]<-NA
      print(paste(ko_names[i],"is missing and will be filtered.",sep=" "))
      perturb_information_ko<-perturb_information_delete_name(perturb_information_ko,ko_names[i])
    }
  }
  names(Zero_ra)<-ko_names
  expression_profile_ko<-expression_profile[,names(perturb_information_ko)]
  perturb_information_ctrl<-perturb_information[perturb_information=="CTRL"]
  expression_profile_ctrl<-expression_profile[,names(perturb_information_ctrl)]
  
  expression_profile_ko<-expression_profile[,names(perturb_information_ko)]
  cellNum_eachKo<-table(perturb_information_ko)
  deci_m_choose=c()
  filter_record<-matrix(rep(NA,length(cellNum_eachKo)*3),length(cellNum_eachKo))
  filter_record[,1]<-cellNum_eachKo
  colnames(filter_record)<-c("original_num","valid_num","invalid_ratio")
  row.names(filter_record)<-names(cellNum_eachKo)
  for(i in 1:length(cellNum_eachKo)){
    print(paste("filtering for perturbation:",names(cellNum_eachKo)[i],sep=" "))
    if(cellNum_eachKo[i]>=cell_num_threshold){
      vargene<-c()
      ko_barcode<-names(perturb_information_ko[perturb_information_ko==names(cellNum_eachKo)[i]])
      expression_profile_ko_each<-expression_profile_ko[,ko_barcode]
      expr_c<-cbind(expression_profile_ko_each,expression_profile_ctrl)
      gene_highUMI<-apply(expr_c,1,mean)
      names_highUMI<-names(gene_highUMI[gene_highUMI>umi])
      expr_c<-expr_c[names_highUMI,]
      
      s1=length(ko_barcode)
      vargene<-apply(expr_c,1,get_varGene,s=s1)
      vargene<-vargene[vargene<pvalue]
      vargene_name<-names(vargene)
      if(length(vargene)<vargene_min_num){
        print(paste("The number of variable genes of",names(cellNum_eachKo)[i],"is less than ",vargene_min_num,",this perturbation will be filtered directory."))
        filter_record[i,2]<-0
        filter_record[i,3]<-(filter_record[i,1]-filter_record[i,2])/filter_record[i,1]
        next
      }
      expression_profile_ctrl_var<-t(expression_profile_ctrl[vargene_name,])
      expression_profile_ko_var<-t(expression_profile_ko_each[vargene_name,])
      a=cosin_dis_diffMatrix(expression_profile_ko_var,expression_profile_ko_var,cpu_num = cpu_num)
      a_median<-apply(a,1,median)
      b=cosin_dis_diffMatrix(expression_profile_ko_var,expression_profile_ctrl_var,cpu_num=cpu_num)
      b_median<-apply(b,2,median)
      perturb_like<-a_median-b_median
      perturb_like<-perturb_like[perturb_like>0]
      filter_record[i,2]<-length(perturb_like)
      filter_record[i,3]<-(filter_record[i,1]-filter_record[i,2])/filter_record[i,1]
      deci_m_choose<-c(deci_m_choose,names(perturb_like))
    }
    else{
      print("The number of cells with this perturbation is less than 30, this perturbation will be filtered directory.")
    }
  }
  perturb_information_filter<-c(perturb_information[deci_m_choose],perturb_information_ctrl)
  cellNum_eachKo_filter<-as.matrix(table(perturb_information_filter))
  filter_record2<-na.omit(filter_record)
  ko_save<-row.names(filter_record2[filter_record2[,3]<filtered_rate,])
  cellNum_eachKo_filter<-cellNum_eachKo_filter[c(ko_save,"CTRL"),]
  cellNum_eachKo_filter<-cellNum_eachKo_filter[cellNum_eachKo_filter>=cell_num_threshold]
  perturb_information_filter<-perturb_information_filter[perturb_information_filter %in% names(cellNum_eachKo_filter)]
  expression_profile_filter<-expression_profile[,names(perturb_information_filter)]
  perturb_information_filter_abandon<-perturb_information[setdiff(names(perturb_information),names(perturb_information_filter))]
  if(plot){
    pdf(plot_path)
    forPlot<-sort(filter_record2[,3])
    barplot(forPlot,names.arg=names(forPlot),xlab="Perturbation",ylab="Invalid_rate",las=2,,ylim=c(0,1))
    dev.off()
  }
  return(list("expression_profile"=expression_profile_filter,"perturb_information"=perturb_information_filter,"perturb_information_abandon"=perturb_information_filter_abandon,"filter_record"=filter_record,"zero_rate"=Zero_ra))
}
# ************************   obtaining high dispersion different genes
Get_high_varGenes<-function(expression_profile,perturb_information,x.low.cutoff=0.01,y.cutoff=0,num.bin=30,plot=FALSE,plot_path="./get_high_var_genes.pdf"){
  logVarDivMean=function(x) return(log(var(x)/mean(x)))
  expMean=function(x) return(log(mean(x)+1))
  data_norm<-function(xy,num.bin){
    seperate<-seq(0,max(xy[,1]),length.out=num.bin+1)
    for(i in 2:length(seperate)){
      xy[which(xy[,1]>seperate[i-1] & xy[,1]<=seperate[i]),3]<-(xy[which(xy[,1]>seperate[i-1] & xy[,1]<=seperate[i]),2]-mean(xy[which(xy[,1]>seperate[i-1] & xy[,1]<=seperate[i]),2]))/sd(xy[which(xy[,1]>seperate[i-1] & xy[,1]<=seperate[i]),2])
    }
    return(xy)
  }
  label=c()
  j=1
  for(i in 1:length(perturb_information)){
    if(perturb_information[i]=="CTRL"){
      label[j]="ctrl"
      j=j+1
    }
    else{
      label[j]="ko"
      j=j+1
    }
  }
  nCountsEndo_ko<-expression_profile[,which(label=="ko")]
  nCountsEndo_ctrl<-expression_profile[,which(label=="ctrl")]
  data.x_ko<-apply(expression_profile,1,expMean)
  data.y_ko<-apply(nCountsEndo_ko,1,logVarDivMean)
  data.y_ko[data.y_ko==-Inf]<-NaN
  mid<-data.y_ko
  mid[is.nan(mid)]<-0
  data.y_ko[is.nan(data.y_ko)]<-min(mid)-1
  data.y_ctrl<-apply(nCountsEndo_ctrl,1,logVarDivMean)
  data.y_ctrl[data.y_ctrl==-Inf]<-NaN
  mid<-data.y_ctrl
  mid[is.nan(mid)]<-0
  data.y_ctrl[is.nan(data.y_ctrl)]<-min(mid)-1
  data.y_diff<-abs(data.y_ko-data.y_ctrl)
  
  diff_xy<-cbind(data.x_ko,data.y_diff,0,1)
  row.names(diff_xy)<-row.names(nCountsEndo_ko)
  colnames(diff_xy)<-c("data.x","data.y","data.norm.y","vargene")
  diff_xy<-data_norm(diff_xy,num.bin)
  diff_xy[is.na(diff_xy[,3]),3]<-0
  diff_xy[which(diff_xy[,1]>x.low.cutoff  & diff_xy[,3]>y.cutoff),4]<-2
  y_choose<-diff_xy[which(diff_xy[,1]>x.low.cutoff),]
  y_choose<-y_choose[order(-y_choose[,3]),]
  if(plot){
    pdf(file=plot_path)
    par(mfrow=c(1,2))
    plot(diff_xy[,1],diff_xy[,3],type="p",xlab="Average expression",pch=16,ylab="Dispersion difference",col=diff_xy[,4])
    plot(1:nrow(y_choose),y_choose[,3],type="b",xlab="Gene number",ylab="Dispersion difference",col=y_choose[,4])
    grid(nx=NA,ny=50,lwd=1,lty=2,col="blue")
    dev.off()
  }
  expression_profile_varGene<-expression_profile[which(diff_xy[,4]==2),]
  return(list("expression_profile"=expression_profile_varGene,"perturb_information"=perturb_information))
}
# ************************   obtain topics in a recommended reasonable range
Get_topics<-function(expression_profile,perturb_information,topic_number=c(4:6),seed_num=2018,burnin=0,thin=500,iter=500){
  require(slam)
  require(topicmodels)
  require(ggplot2)
  print("Adjusting data for topic model inputting ...")
  #adjust data for topic model
  label=c()
  j=1
  for(i in 1:length(perturb_information)){
    if(perturb_information[i]=="CTRL"){
      label[j]="ctrl"
      j=j+1
    }
    else{
      label[j]="ko"
      j=j+1
    }
  }
  gene_counts_sum<-apply(expression_profile,1,sum)
  expression_profile<-expression_profile[which(gene_counts_sum>0),]
  nCountsEndo_ctrl<-expression_profile[,which(label=="ctrl")]
  for(i in 1:nrow(expression_profile)){
    if(mean(nCountsEndo_ctrl[i,])>0){
      expression_profile[i,]=(expression_profile[i,]-mean(nCountsEndo_ctrl[i,]))/mean(nCountsEndo_ctrl[i,])
    }
  }
  expression_profile<-round((expression_profile+abs(min(expression_profile)))*10)
  #
  topic_model_list<-list()
  control=list(seed=seed_num,burnin=burnin,thin=thin,iter=iter)
  dtm<-as.simple_triplet_matrix(t(expression_profile))
  i=1
  print("It may take a few hours. Please wait patiently.")
  for(k in topic_number){
    print(paste("now the calculating topic number is",k,sep=" "))
    topic_model=LDA(dtm,k=k,method="Gibbs",control=control)
    topic_model_list[[i]]=topic_model
    i<-i+1
  }
  return(list("models"=topic_model_list,"perturb_information"=perturb_information))
}
# ************************   selecting the optimal topic number automatically
Select_topic_number<-function(topic_model_list,plot=FALSE,plot_path="./select_topic_number.pdf"){
  require(ggplot2)
  topic_specificity_score<-c()
  cell_specificity_score<-c()
  combined_specificity_score<-c()
  topic_name=c()
  for(i in 1:length(topic_model_list)){
    topic_model<-topic_model_list[[i]]@gamma
    topic_num<-ncol(topic_model)
    col_varDivSq<-apply(topic_model,2,var)/apply(topic_model,2,mean)^2
    row_var<-apply(topic_model,1,var)
    topic_specificity_score[i]=log(mean(col_varDivSq))
    cell_specificity_score[i]=log(mean(row_var))
    combined_specificity_score[i]=(topic_specificity_score[i]+cell_specificity_score[i])/2
    topic_name[i]=paste(topic_num,"topic",sep="")
  }
  combine_min<-min(combined_specificity_score)
  for(i in 1:length(combined_specificity_score)){
    combined_specificity_score[i]=(combined_specificity_score[i]-combine_min)
  }
  if(plot){
    pdf(file=plot_path)
    topic_number<-factor(topic_name,levels = topic_name)
    selectTopic_dataFrame<-data.frame(topic_number,score=combined_specificity_score)
    p=ggplot(selectTopic_dataFrame,aes(x=topic_number,y=score,group=1))+theme(axis.text.x=element_text(angle=45,size=10))+geom_line()+geom_point(size=4)
    print(p)
    dev.off()
  }
  m=order(combined_specificity_score,decreasing = T)[1]
  return(topic_model_list[[m]])
}
# *********************   annotating each topic's functions for Hs(homo sapiens) or Mm(mus musculus)
Topic_func_anno <-function(model,species="Hs",topNum=5,plot=TRUE,plot_path="./topic_annotation_GO.pdf"){
  require(clusterProfiler)
  require(reshape2)
  require(Biostrings)
  require(dplyr)
  if(species=="Hs"){
    library(org.Hs.eg.db)
    organism="hsa"
    Alia_entrez<-org.Hs.egALIAS2EG  
    entrez_Alia<-org.Hs.egSYMBOL
    OrgDb<-"org.Hs.eg.db"
  }else if(species=="Mm"){
    library(org.Mm.eg.db)
    organism="mmu"
    Alia_entrez<-org.Mm.egALIAS2EG  
    entrez_Alia<-org.Mm.egSYMBOL
    OrgDb<-"org.Mm.eg.db"
  }else{
    stop("species should be 'Hs' or 'Mm'")
  }
  my_beta <- model@beta
  topic_num<-nrow(my_beta)
  my_geneName<-model@terms
  colnames(my_beta) <- my_geneName
  rownames(my_beta) <- paste('Topic',1:nrow(my_beta),sep=" ")
  x<-Alia_entrez 
  y<-entrez_Alia
  my_geneName<-my_geneName[my_geneName %in% mappedkeys(x)]#filter some unrecognized alia name
  my_beta<-my_beta[,my_geneName]
  my_geneID<-as.list(x[my_geneName])
  col_index=c()
  geneID=c()
  i=1
  for(k in 1:length(my_geneID)){
    if(length(my_geneID[[k]])==1){
      col_index[i]=k
      geneID[i]=my_geneID[[k]]
      i=i+1
    }
  }
  my_beta<-my_beta[,col_index]
  colnames(my_beta)<-geneID
  my_beta <- exp(my_beta)
  data_melt <- melt(my_beta)
  colnames(data_melt)<-c("topics","gene","value")
  data_list<-split(data_melt,data_melt$topics)
  topic_id=list()
  for(i in 1:length(data_list)){
    cutoff<-quantile(data_list[[i]]$value,0.9)
    entr_character<-as.character(data_list[[i]][data_list[[i]]$value>=cutoff,"gene"])
    topic_id[i]=list(entr_character)
  }
  topic_id_name=c()
  for(i in 1:length(topic_id)){
    topic_id_name[i]=paste("Topic",i,sep=" ")
  }
  names(topic_id)<-topic_id_name    
  topic_geneName<-topic_id  
  for(i in 1:length(topic_geneName)){  
    topic_geneName[[i]]<-as.character(as.list(y[topic_id[[i]]]))    
  }
  Compare_go <- compareCluster(geneCluster=topic_id, fun="enrichGO",OrgDb=OrgDb,ont="BP",minGSSize=1,qvalueCutoff=1,pvalueCutoff=1)
  enrich_result<-Compare_go@compareClusterResult
  enrich_result<-enrich_result[order(enrich_result$Cluster,enrich_result$qvalue),]
  ex<-enrich_result %>% group_by(Cluster) %>% summarise(enrich_count=length(Cluster))
  ex<-as.data.frame(ex)
  ex$enrich_count<-cumsum(ex$enrich_count)
  enrich_number=topNum
  enrich_number2=topNum
  enrich_choose_index=c()
  enrich_choose_index=c(1:enrich_number2)
  for(i in 1:(nrow(ex)-1)){
    enrich_choose_index[(enrich_number2+1):(enrich_number2+enrich_number)]=c((ex$enrich_count[i]+1):(ex$enrich_count[i]+enrich_number))
    enrich_number2=enrich_number2+enrich_number
  }
  enrich_result<-enrich_result[enrich_choose_index,]
  topic_annotation_result<-enrich_result[,c("Cluster","Description","qvalue","Count")]
  if(plot){
    require(ggplot2)
    topic_annotation_result<-na.omit(topic_annotation_result)
    topic_annotation_result$Description<-factor(as.character(topic_annotation_result$Description),levels=rev(unique(as.character(topic_annotation_result$Description))))
    pdf(file=plot_path,width=14,height=10)
    p=ggplot(topic_annotation_result,aes(Cluster,Description)) +
      geom_point(aes(color=qvalue,size=Count)) +
      scale_color_gradient(low = "red", high = "blue")+
      theme_bw() +
      theme(axis.text.x=element_text(angle=45,size=12))+
      theme(axis.text.y=element_text(size=12))+
      theme(axis.title =element_text(size = 0))
    print(p)
    dev.off()
  }
  return(list("topic_annotation_result"=topic_annotation_result,"topic_annotation_geneName"=topic_geneName))
}
# ********************   evaluating off target effect
Get_offtarget<-function(offTarget_results,expression_profile,perturb_information,sgRNA_information){
  offTargetGene<-offTarget_results$offtarget[,c("name","gene")]
  require(hash)
  grna_gene_hash<-hash()
  sgRNA_information<-sgRNA_information[names(perturb_information)]
  for(i in 1:length(sgRNA_information)){
    grna_gene_hash[sgRNA_information[i]]<-perturb_information[i]
  }
  offTargetGene$target<-NA
  for(i in 1:nrow(offTargetGene)){
    if(has.key(as.character(offTargetGene$name[i]),grna_gene_hash)){
      offTargetGene$target[i]<-grna_gene_hash[[as.character(offTargetGene$name[i])]]
    }
  }
  offTargetGene<-na.omit(offTargetGene)
  offTargetGene<-offTargetGene[offTargetGene$gene!="",]
  offTargetGene<-unique(offTargetGene)
  offTargetGene<-offTargetGene[offTargetGene$target!=offTargetGene$gene,]
  offTargetGene$off<-NA
  control_data<-expression_profile[,names(perturb_information[which(perturb_information=="CTRL")])]
  for(i in 1:nrow(offTargetGene)){
    offTarget_data<-expression_profile[,names(sgRNA_information[which(sgRNA_information==as.character(offTargetGene$name[i]))])]
    if(as.character(offTargetGene[i,"gene"]) %in% row.names(offTarget_data)){
      offgene<-offTarget_data[as.character(offTargetGene[i,"gene"]),]
    }else{
      offgene<-NA
    }
    if(as.character(offTargetGene[i,"target"]) %in% row.names(offTarget_data)){
      ongene<-offTarget_data[as.character(offTargetGene[i,"target"]),]
    }else{
      ongene<-NA
    }
    if(!is.na(offgene) && !is.na(ongene)){
      r_off<-cor(offgene,ongene)
      offgene_ctrl<-control_data[offTargetGene[i,"gene"],]
      ongene_ctrl<-control_data[offTargetGene[i,"target"],]
      r_ctrl_off<-cor(offgene_ctrl,ongene_ctrl)
      if(!is.na(r_off) && !is.na(r_ctrl_off) && (r_off-r_ctrl_off)/r_ctrl_off>0.01){
        offTargetGene$off[i]="yes"
      }
    }else{
      offTargetGene$off[i]=NA
    }
  }
  offTargetGene<-na.omit(offTargetGene)
  offTargetGene_hash<-hash()
  offTargetGene<-offTargetGene[,-1]
  offTargetGene<-unique(offTargetGene)
  if(nrow(offTargetGene)>0){
    for(i in 1:nrow(offTargetGene)){
      if(offTargetGene$off[i]=="yes"){
        if(has.key(offTargetGene$target[i],offTargetGene_hash)){
          offTargetGene_hash[offTargetGene$target[i]]<-paste(offTargetGene_hash[[offTargetGene$target[i]]],offTargetGene$gene,sep=",")
        }else{
          offTargetGene_hash[offTargetGene$target[i]]<-offTargetGene$gene[i]
        }
      }
    }
  }
  return(offTargetGene_hash)
}
##############################   perturbation effect prioritzing   ##################################################
# *******************   calculating topics distribution for each cell
Diff_topic_distri<-function(model,perturb_information,plot=FALSE,plot_path="./distribution_of_topic.pdf"){
  require(reshape2)
  require(dplyr)
  require(entropy)
  options(warn = -1)
  pmatrix<-model@gamma
  row.names(pmatrix)<-model@documents
  topicNum<-ncol(pmatrix)
  topicName<-paste('Topic',1:topicNum,sep='')
  colnames(pmatrix)<-paste('Topic',1:topicNum,sep='')
  p.matrix<-data.frame(pmatrix,samples=rownames(pmatrix),knockout=perturb_information)
  p.matrix <- melt(p.matrix,id=c('samples','knockout'))
  ko_name<-as.character(unique(p.matrix$knockout))
  t_D<-as.data.frame(matrix(rep(0,length(ko_name)*ncol(pmatrix)*4),ncol = 4))
  colnames(t_D)<-c("knockout","topic","t_D","pvalue")
  p.step1=p.matrix %>% group_by(knockout,variable) %>% summarise(number=sum(value))
  total_number=sum(p.step1$number)
  p.step2=p.step1 %>% group_by(knockout) %>% summarise(cellNum=sum(number))
  p.step1=merge(p.step1,p.step2,by='knockout')
  p.step3<-(p.step1$number)/(p.step1$cellNum)
  p.step4<-data.frame(p.step1,ratio=p.step3)
  p.step4$ctrlNum<-p.step4[which(p.step4$knockout=="CTRL"),"cellNum"]
  p.step4$ctrl_ratio<-p.step4[which(p.step4$knockout=="CTRL"),"ratio"]
  p.step4$diff_index<-(p.step4$ratio-p.step4$ctrl_ratio)
  cell_num_min<-round(min(p.step4$cellNum)*0.9)
  k=1
  for(i in topicName){
    p.matrix.topic<-p.matrix[p.matrix$variable==i,]
    ctrl_topic<-p.matrix.topic[p.matrix.topic$knockout=="CTRL",4]
    ctrl_topic_z<-(ctrl_topic-mean(ctrl_topic))/sqrt(var(ctrl_topic))
    for(j in ko_name){
      ko_topic<-p.matrix.topic[p.matrix.topic$knockout==j,4]
      ko_topic_z<-(ko_topic-mean(ctrl_topic))/sqrt(var(ctrl_topic))
      t_D[k,1]<-j
      t_D[k,2]<-i
      test_s<-matrix(rep(0,2*1000),1000)
      for(t in 1:1000){
        ko_topic_s<-sample(ko_topic,cell_num_min)
        test<-t.test(ko_topic_s,ctrl_topic)
        test_s[t,1]<-test$statistic
      }
      t_D[k,3]<-sort(test_s[,1])[round(length(test_s[,1])/2)]
      k<-k+1
    }
  }
  t_D<-t_D[order(t_D$knockout),]
  p.step4$t_D<-t_D$t_D
  p.step4$t_D_ctrl<-p.step4[p.step4$knockout=="CTRL","t_D"]
  p.step4$t_D_diff<-p.step4$t_D-p.step4$t_D_ctrl
  t_D_sum<-p.step4 %>% group_by(knockout) %>% summarise(t_D_sum=sum(abs(t_D_diff)))
  t_D_sum<-as.data.frame(t_D_sum)
  p.step5=merge(p.step4,t_D_sum,by='knockout')
  t_D_sum2<-p.step4 %>% group_by(knockout) %>% summarise(t_D_sum2=sum(abs(t_D)))
  t_D_sum2<-as.data.frame(t_D_sum2)
  p.step5=merge(p.step5,t_D_sum2,by='knockout')
  p.step5$perturb_percent<-abs(p.step5$t_D)/p.step5$t_D_sum2
  if(plot){
    topic_perturb<-function(distri_diff,plot_path){
      require(gplots)
      require(reshap2)
      perturb_topic<-distri_diff[,c("knockout","variable","t_D_diff")]
      perturb_topic_matrix<-dcast(perturb_topic,knockout ~ variable)
      row.names(perturb_topic_matrix)<-perturb_topic_matrix$knockout
      perturb_topic_matrix<-as.matrix(perturb_topic_matrix[,-1])
      pdf(plot_path)
      heatmap.2(perturb_topic_matrix,col=bluered,dendrogram="both",adjCol=c(NA,1),cexCol = 0.5,cexRow = 0.5,srtCol = 45, srtRow=-45,key=TRUE,trace="none", breaks=seq.int(from = min(perturb_topic_matrix), to = max(perturb_topic_matrix), length.out = 100),hclustfun=hclust)
      dev.off()
    }
    topic_perturb(p.step5,plot_path = plot_path)
  }
  return(p.step5)
}
# *******************  calculating overall perturbation effect ranking list
Rank_overall<-function(distri_diff,offTarget_hash=hash(),output=FALSE,file_path="./rank_overall.txt"){
  require(dplyr)
  require(entropy)
  require(hash)
  KO_offTarget_hash<-hash()
  rank_overall<-distri_diff[,c("knockout","t_D_sum")]
  rank_overall<-unique(rank_overall)
  rank_overall<-rank_overall[order(rank_overall$t_D_sum,decreasing=T),]
  rank_overall$ranking=1:nrow(rank_overall)
  row.names(rank_overall)=1:nrow(rank_overall)
  rank_overall$off_target<-"none"
  for(i in 1:nrow(rank_overall)){
    ko_gene_arr<-unlist(split(rank_overall$knockout,","))
    off_target_arr<-c()
    k=1
    for(j in ko_gene_arr){
      if(has.key(j,offTarget_hash)){
        off_target_arr[k]=offTarget_hash[[j]]
        k=k+1
      }
    }
    off_target=off_target_arr[1]
    if(length(off_target_arr)>1){
      for(k in 2:length(off_target_arr)){
        off_target<-paste(off_target,off_target_arr[k],sep=",")
      }
    }
    if(!is.null(off_target)){
      KO_offTarget_hash[rank_overall$off_target[i]]=off_target
      rank_overall$off_target[i]=off_target
    }
  }
  rankOverall_result<-rank_overall[,c("knockout","ranking","t_D_sum","off_target")]
  rankOverall_result<-rankOverall_result[rankOverall_result$knockout!="CTRL",]
  colnames(rankOverall_result)<-c("perturbation","ranking","Score","off_target")
  if(output){
    write.table(rankOverall_result,file_path,col.names=T,row.names=F,quote=F,sep="\t")
  }
  return(rankOverall_result)
}
#********************   calculating topic-specific ranking list by considering efficiency and specificity
Rank_specific<-function(distri_diff,output=FALSE,file_path="./rank_specific.txt"){
  distri_diff<-distri_diff[order(distri_diff$variable,-abs(distri_diff$t_D)),c("variable","knockout","t_D","perturb_percent")]
  t_D_max<-distri_diff %>% group_by(variable) %>% summarise(t_D_max=max(abs(t_D)))
  t_D_min<-distri_diff %>% group_by(variable) %>% summarise(t_D_min=min(abs(t_D)))
  perturb_percent_max<-distri_diff %>% group_by(variable) %>% summarise(perturb_percent_max=max(perturb_percent))
  perturb_percent_min<-distri_diff %>% group_by(variable) %>% summarise(perturb_percent_min=min(perturb_percent))
  rank_topic_specific<-merge(distri_diff,merge(t_D_min,merge(t_D_max,merge(perturb_percent_max,perturb_percent_min))))
  rank_topic_specific$t_D_standard<-(abs(rank_topic_specific$t_D)-rank_topic_specific$t_D_min)/(rank_topic_specific$t_D_max-rank_topic_specific$t_D_min)
  rank_topic_specific$perturb_percent_standard<-(rank_topic_specific$perturb_percent-rank_topic_specific$perturb_percent_min)/(rank_topic_specific$perturb_percent_max-rank_topic_specific$perturb_percent_min)
  rank_topic_specific$recommand_score<-rank_topic_specific$t_D_standard+rank_topic_specific$perturb_percent_standard
  rank_topic_specific<-rank_topic_specific[order(rank_topic_specific$knockout),]
  rank_topic_specific$recommand_score_ctrl<-rank_topic_specific[rank_topic_specific$knockout=="CTRL","recommand_score"]
  rank_topic_specific<-rank_topic_specific[rank_topic_specific$recommand_score>rank_topic_specific$recommand_score_ctrl,]
  rank_topic_specific<-rank_topic_specific[order(rank_topic_specific$variable,-rank_topic_specific$recommand_score),]
  topic_times<-table(as.character(rank_topic_specific$variable))
  ranking<-c()
  for(i in topic_times){
    ranking<-c(ranking,1:i)
  }
  rank_topic_specific$ranking<-ranking
  rank_topic_specific<-rank_topic_specific[,c("variable","knockout","ranking")]
  row.names(rank_topic_specific)<-1:nrow(rank_topic_specific)
  colnames(rank_topic_specific)<-c("topic","perturbation","ranking")
  if(output){
    write.table(rank_topic_specific,file_path,col.names=T,row.names=F,quote=F,sep="\t")
  }
  return(rank_topic_specific)
}
#********************   relationship between different perturbations
Correlation_perturbation<-function(distri_diff,cutoff=0.9,gene="all",plot=FALSE,plot_path="./correlation_network.pdf",output=FALSE,file_path="./correlation_perturbation.txt"){
  require(gplots)
  require(reshape2)
  distri_diff<-distri_diff[which(distri_diff$knockout!="CTRL"),]
  correlation<-function(matrix,method="pearson"){
    sample_num<-nrow(matrix)
    cor_matrix<-matrix(rep(1,sample_num^2),sample_num)
    colnames(cor_matrix)<-row.names(matrix)
    row.names(cor_matrix)<-row.names(matrix)
    for(i in 1:(sample_num-1)){
      for(j in (i+1):sample_num){
        cor_matrix[i,j]<-cor(matrix[i,],matrix[j,],method = method)
        cor_matrix[j,i]<-cor_matrix[i,j]
      }
    }
    return(cor_matrix)
  }
  perturb_topic<-distri_diff[,c("knockout","variable","t_D_diff")]
  perturb_topic_matrix<-dcast(perturb_topic,knockout ~ variable)
  row.names(perturb_topic_matrix)<-perturb_topic_matrix$knockout
  perturb_topic_matrix<-as.matrix(perturb_topic_matrix[,-1])
  perturb_topic_cor<-correlation(perturb_topic_matrix)
  perturb_cor<-melt(perturb_topic_cor)
  colnames(perturb_cor)<-c("Perturbation_1","Perturbation_2","Correlation")
  perturb_cor<-perturb_cor[perturb_cor$Perturbation_1!=perturb_cor$Perturbation_2,]
  perturb_cor<-perturb_cor[order(perturb_cor$Correlation),]
  perturb_cor<-perturb_cor[seq(1,nrow(perturb_cor),by=2),]
  perturb_cor<-perturb_cor[order(-abs(perturb_cor$Correlation)),]
  perturb_cor<-perturb_cor[order(perturb_cor$Perturbation_1),]
  if(gene!="all"){
    for(i in 1:length(gene)){
      if(!(gene[i] %in% distri_diff$knockout)){
        print(paste("Warning! Can't find",gene[i],",please check it again!"))
        stop()
      }
    }
    perturb_cor<-perturb_cor[(perturb_cor$Perturbation_1 %in% gene) | (perturb_cor$Perturbation_2 %in% gene),]
  }
  if(output){
    write.table(perturb_cor,file_path,col.names=T,row.names=F,quote=F,sep="\t")
  }
  if(plot){
    require(igraph)
    pdf(plot_path)
    #cutoff<-quantile(abs(perturb_cor$Correlation),quanti)
    t<-perturb_cor[abs(perturb_cor$Correlation)>cutoff,]
    t$direction<-sign(t$Correlation)
    color_e<-c()
    for(i in 1:nrow(t)){
      if(t$direction[i]==-1){
        color_e[i]="blue"
      }else{
        color_e[i]="red"
      }
    }
    opar <- par(no.readonly = TRUE)
    par(mar = c(0,0,0,0))
    g <- graph.data.frame(t, directed = FALSE) 
    E(g)$color=color_e
    plot(g, layout = layout.fruchterman.reingold)
    par(opar)
    dev.off()
  }
  return(perturb_cor)
}
#********************   compare analysis if there are different condition
Diff_perturb_effect<-function(rank_overall_condition_1,rank_overall_condition_2,fold_change=2,plot=FALSE,plot_path="./perturbation_effect_difference.pdf",output=FALSE,file_path="./perturbation_effect_difference.txt"){
  require(ggplot2)
  rank_overall_condition_1<-rank_overall_condition_1[rank_overall_condition_1$perturbation!="CTRL",]
  rank_overall_condition_2<-rank_overall_condition_2[rank_overall_condition_2$perturbation!="CTRL",]
  row.names(rank_overall_condition_1)<-rank_overall_condition_1$perturbation
  row.names(rank_overall_condition_2)<-rank_overall_condition_2$perturbation
  common_perturbation<-sort(intersect(rank_overall_condition_1$perturbation,rank_overall_condition_2$perturbation))
  compare_matrix<-matrix(rep(0,length(common_perturbation)*4),ncol=4)
  row.names(compare_matrix)<-common_perturbation
  colnames(compare_matrix)<-c("perturbation","condition1","condition2","impact_fold_change")
  compare_matrix<-as.data.frame(compare_matrix)
  compare_matrix[,1]<-row.names(compare_matrix)
  compare_matrix[,2]<-rank_overall_condition_1[common_perturbation,3]
  compare_matrix[,3]<-rank_overall_condition_2[common_perturbation,3]
  compare_matrix[,2]<-compare_matrix[,2]/sum(compare_matrix[,2])
  compare_matrix[,3]<-compare_matrix[,3]/sum(compare_matrix[,3])
  compare_matrix[,4]<-compare_matrix[,2]/compare_matrix[,3]
  if(plot){
    pdf(plot_path)
    p=ggplot(compare_matrix,aes(x=perturbation,y=impact_fold_change,group=1))+geom_text(aes(label=perturbation),nudge_x = -0.2,nudge_y = 0.05)+geom_line()+geom_point(size=3)+xlab("perturbation")+ylab("impact fold change")+theme_bw()+theme(axis.text.x=element_text(angle=90,size=0))+geom_hline(aes(yintercept=fold_change),col="red",linetype="dashed")
    print(p)
    dev.off()
  }
  compare_matrix<-compare_matrix[order(-compare_matrix$impact_fold_change),]
  difference_result<-compare_matrix[which(compare_matrix$impact_fold_change>fold_change),]
  if(output){
    write.table(difference_result,file_path,col.names=T,row.names=F,quote=F,sep="\t")
  }
  return(difference_result)
}

