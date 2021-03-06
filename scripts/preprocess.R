library(Seurat)
library(tidyverse)

## see https://bitbucket.org/snakemake/snakemake/issues/917/enable-stdout-and-stderr-redirection
log <- file(snakemake@log[[1]], open="wt")
sink(log)
sink(log, type="message")

seurat_obj<- readRDS(snakemake@input[[1]])
k<- snakemake@wildcards[["k"]]
resolution<- snakemake@wildcards[["resolution"]]
pc.use<- snakemake@wildcards[["pc"]]


PreprocessSubsetData<- function(object,
                                variable.features.n = 3000,
                                num.pc = 20,
                                pc.use = NULL,
                                #workers = 2,
                                score.thresh = 1e-5,
                                sig.pc.thresh = 0.05,
                                n.start = 100,
                                nn.eps = 0,
                                resolution = 0.8,
                                k.param = 30,
                                ...){
        ## use future for parallelization
        ##future::plan("multiprocess", workers = workers)
        meta.data.colnames<- object@meta.data %>% colnames()
        vars.to.regress<- c("percent.mt","nFeature_RNA")
        # in case the seurat object does not have percent.mito in metadata
        vars.to.regress<- vars.to.regress[vars.to.regress %in% meta.data.colnames]
        # default is on variable features only, omit the features argument
        # SCTransform replaces NormalizeData, ScaleData and FindVariableFeatures
        object<- SCTransform(object, vars.to.regress = vars.to.regress,
                             variable.features.n = variable.features.n, verbose = FALSE)

        object<- RunPCA(object = object, features = VariableFeatures(object = object),
                        npcs = num.pc)

        if (is.null(pc.use)){
                object<- JackStraw( object = object, num.replicate = 100, dims = num.pc)

                object <- ScoreJackStraw(object = object, dims = 1:num.pc, score.thresh = score.thresh)

                PC_pvalues<- object@reductions$pca@jackstraw@overall.p.values

                ## determin how many PCs to use.
                pc.use<- min(which(PC_pvalues[,"Score"] > sig.pc.thresh)) -1

        }

        # add significant pc number to metadata, need to have names same as the cells
        pc.use.meta<- rep(pc.use, length(colnames(object)))
        names(pc.use.meta)<- colnames(object)
        object<- AddMetaData(object = object, metadata = pc.use.meta, col.name = "pc.use")
        object<- FindNeighbors(object, dims = 1:pc.use, k.param = k.param, nn.eps = nn.eps,
                               verbose = FALSE, reduction = "pca", force.recalc = TRUE)
        object <- FindClusters(object = object, reduction.type = "pca",
                                n.start = n.start,
                                resolution = resolution,
                                verbose = FALSE)
        return(object)
}


PreprocessSubsetData_pars<- snakemake@params[["PreprocessSubsetData_pars"]]
## this is not subsetted data, but the PreprocessSubsetData function can be used as well for any seurat object
seurat_obj<- eval(parse(text=paste("PreprocessSubsetData", "(", "seurat_obj,", "k.param=", k, ",", "pc.use=", pc.use, ",",
                                   "resolution=", resolution, ",", PreprocessSubsetData_pars, ")")))
saveRDS(seurat_obj, file = paste0("full_sample_preprocess/full_sample_", "k_", k, "_resolution_", resolution, "_PC_", pc.use, ".rds"))
