# https://github.com/ropensci/spocc
# https://docs.ropensci.org/rgbif/
# https://docs.ropensci.org/rvertnet/articles/rvertnet.html

# GBIF User Download Page:
# https://www.gbif.org/user/download

suppressPackageStartupMessages(
  suppressWarnings({
    library(data.table)
    library(dplyr)
    library(purrr)
    library(rgbif)
    library(spocc)
    library(rvertnet)
    # remotes::install_github("callumgwtaylor/snakes")
    library(snakes)
    library(taxize)
    library(sf)
    library(ggplot2)
  })
)
base::readRenviron(".Renviron")
set.seed(19)

us.venomous.snakes <- snakes::snake_country_data %>% 
  as.data.table() %>%
  .[country_name == "United States of America", 
    .(snake_common_name, snake_species)] 

na.reptiles <- fread("data/reptiles_of_northern_america_parsed.csv") %>%
  .[, 1:9, with=F] %>%
  unique()
if (!file.exists("data/all.occ.rds")) {
  all.occ <- na.reptiles$Species %>%
    set_names() %>%
    purrr::map(~rgbif::occ_data(scientificName = .x))
  saveRDS(all.occ, "data/all.occ.rds")
} else {
  all.occ <- readRDS("data/all.occ.rds")
}

dwnld.tk <- function(key, extent) {
  tk <- tryCatch({
    occ_download(pred("taxonKey", key), 
                 pred_within(extent),
                 format = "SIMPLE_CSV") %>%
      occ_download_wait()
  }, error=function(e) {
    browser()
    print(e)
  })
  d <- occ_download_get(tk$key, path = "data", overwrite = T) %>%
    occ_download_import()
  
  utils::unzip(file.path("data", paste0(tk$key, ".zip")), 
               exdir = file.path("data", tk$key), overwrite = T) 
  file.remove(file.path("data", paste0(tk$key, ".zip")))
  
  d <- fread(file.path("data", tk$key, paste0(tk$key, ".csv")))
  unlink(file.path("data", tk$key), recursive=T)
  if (nrow(d) > 0) {
    fname <- gsub(" ", "_", d$species[[1]]) %>%
      gsub("[^[:alnum:]_]", "", .) %>%
      tolower() %>%
      paste0(., "_", key, ".csv.gz")
    f <- file.path("data", "species_obs", fname)
    fwrite(d, f)
  } 
  meta <- file.path("data", "species_obs", paste0(key, ".rds"))
  # Save metadata
  saveRDS(tk, meta)
  return(meta)
}

get.species.obs <- function(.data, extent) {
  if (!is.null(.data)) {
    tks <- .data %>%
      filter(publishingCountry == "US") %>%
      .$taxonKey %>%
      unique()
    if (length(tks) > 0) {
      out.files <- purrr::map2(tks, 1:length(tks), function(tk, i) {
        f <- file.path("data", "species_obs", paste0(tk, ".rds"))
        if (!file.exists(f)) {
          f <- dwnld.tk(tk, extent)
          cat(format(Sys.time()), "Saved metadata for", 
              paste0("[", i, "/", length(tks), "]"), "to", f, "\n")
        } else {
          cat(format(Sys.time()), paste0("[", i, "/", length(tks), "]"), 
          "already exists\n")
        }
        
      })
    } else {
      cat(format(Sys.time()), "No data for",  .data$species[[1]], "\n")
    }
  } else {
    cat(format(Sys.time()), "No data found\n")
  }
}


conus <- sf::read_sf("data/conus.shp")
.crs <- sf::st_as_text(st_crs(conus))
.extent <- sf::st_bbox(conus)
wkt.extent <- sprintf("POLYGON((%s %s, %s %s, %s %s, %s %s, %s %s))",
                      .extent["xmin"], .extent["ymin"],
                      .extent["xmin"], .extent["ymax"],
                      .extent["xmax"], .extent["ymax"],
                      .extent["xmax"], .extent["ymin"],
                      .extent["xmin"], .extent["ymin"])


purrr::walk2(names(all.occ), 1:length(all.occ), function(s, i) {
  cat(format(Sys.time()), paste0("[", i, "/", length(all.occ), "]"), 
      "Downloading data for", s, "\n")
  get.species.obs(all.occ[[s]]$data, wkt.extent)
})


dt <- purrr::map(
  list.files("data/species_obs", full.names=T, 
             pattern="\\.csv\\.gz"), 
  ~{
    fread(.x) %>%
      .[!(basisOfRecord %in% c("PRESERVED_SPECIMEN", "FOSSIL_SPECIMEN"))] %>%
      .[!is.na(decimalLatitude) & !is.na(decimalLongitude)] %>%
      .[, `:=` (eventDate = suppressWarnings(lubridate::as_date(eventDate)),
                dateIdentified = NULL,
                typeStatus = NULL)] %>%
      .[!is.na(eventDate) & eventDate >= as.Date("2000-01-01")]
  }
) %>% rbindlist() 

# Examine issues
dt$issue %>% 
  unique() %>% 
  paste(collapse=";") %>% 
  stringr::str_split(pattern=";") %>% 
  .[[1]] %>% unique() %>% sort()

dt.sf <- dt[occurrenceStatus == "PRESENT", 
            .(species=as.factor(species), family=as.factor(family),
              order=as.factor(order), class=as.factor(class),
              phylum=as.factor(phylum), eventDate, issue, basisOfRecord,
              decimalLatitude, decimalLongitude)] %>%
  sf::st_as_sf(crs=sf::st_crs(4326),
               coords=c("decimalLongitude", "decimalLatitude"))%>%
  sf::st_intersection(conus) %>%
  unique()

# Plot the map
ggplot() +
  geom_sf(data=conus) +
  geom_sf(data=dt.sf, aes(color=species), alpha=0.5) +
  scale_color_manual(values = rainbow(length(unique(dt.sf$species)))) +
  theme_minimal()
