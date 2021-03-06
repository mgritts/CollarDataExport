# library(data.table)
# library(leaflet)
# library(ggplot2)
# library(sp)
# library(adehabitatHR)

CollarMap <- function(dataframe) {
  df <- as.data.table(dataframe)
  df <- df[complete.cases(df[, .(long_x, lat_y)])]
  df_lines <- df[, .SD[c(seq(1, .N, 20), .N)], by = ndowid]
  unq_id <- unique(df[, ndowid])
  map <- leaflet() %>% addProviderTiles("Esri.WorldTopoMap")
  
  for (n in unq_id) {
    d <- df_lines[ndowid == n]
    dp <- d[, .SD[c(1, .N)]]
    
    map <- addPolylines(map, lng = d$long_x, lat = d$lat_y,
                        weight = 2, color = "black", opacity = .4)
    map <- addCircleMarkers(map, lng = dp$long_x, lat = dp$lat_y,
                            stroke = FALSE, radius = 4, color = "navy",
                            fillOpacity = 1,
                            popup = paste("NDOW ID:", n))
  }
  return(map)
}

Calculate_NSD <- function(dat) {
  dat <- as.data.frame(dat)
  #dat$timestamp <- as.character(dat$timestamp)
  #dat$timestamp <- as.POSIXlt.character(dat$timestamp, 
  #                                      format = ("%m/%d/%Y %H:%M:%S %p"))
  dat <- dat[complete.cases(dat[, c("long_x", "lat_y")]), ]
  geocoord <- sp::SpatialPoints(cbind(as.numeric(dat$long_x),
                                      as.numeric(dat$lat_y)),
                                proj4string = sp::CRS("+proj=longlat"))
  utmcoord <- as.data.frame(sp::spTransform(geocoord, sp::CRS("+proj=utm +zone=11")))
  colnames(utmcoord) <- c("Easting", "Northing")
  dat <- cbind(dat, utmcoord)
  unq_id <- unique(dat$ndowid)
  df <- data.frame()
  for (i in unq_id) {
    x <- dat[dat$ndowid == i, ]
    x$NSD <- (x$Easting - x$Easting[1])**2 + (x$Northing - x$Northing[1])**2
    df <- rbind(df, x)
  }
  return(df)
}

Plot_NSD <- function(dataframe) {
  p <- ggplot(dataframe, aes(x = date, y = NSD, group = ndowid)) +
    geom_line(color = 'firebrick4', size = .75) +
    facet_wrap(~ndowid) +
    labs(y = 'Net Squared Displacement') +
    theme(panel.background = element_rect(fill = 'white'),
          plot.background = element_rect(fill = 'white'),
          panel.grid.major.x = element_line(color = 'grey75', size = 1, linetype = 'dotted'),
          panel.grid.minor.x = element_blank(),
          panel.grid.major.y = element_line(color = 'grey75', size = 1, linetype = 'dotted'),
          panel.grid.minor.y = element_blank(),
          axis.title.x = element_blank(),
          axis.title.y = element_text(color = 'grey50', size = 14),
          axis.text.x = element_text(color = 'grey50', size = 10),
          axis.text.y = element_blank(),
          axis.ticks = element_blank(),
          strip.background = element_blank(),
          strip.text = element_text(color = 'grey50', size = 12))
  return(p)
}

DeviceMapping <- function(dataframe, basemap = "Esri.WorldTopoMap") {
  dat <- as.data.table(dataframe)
  dat <- dat[complete.cases(dat[, .(long_x, lat_y)])]
  unique.id <- unique(dat$ndowid)
  pal <- ggthemes::gdocs_pal()(20)
  
  device.map <- leaflet() %>% 
    addProviderTiles(basemap)
  layer.group <- list()
  
  for(i in 1:length(unique.id)) {
    df <- dat[ndowid == unique.id[i]]
    device.map <- addPolylines(device.map, 
                               lng = df$long_x, lat = df$lat_y,
                               group = as.character(unique.id[i]),
                               color = "grey",
                               weight = 1
    )
    #df <- df[, .SD[c(seq(1, .N, 5), .N)]]
    device.map <- addCircleMarkers(device.map,
                                   lng = df$long_x, lat = df$lat_y,
                                   group = as.character(unique.id[i]),
                                   radius = 2,
                                   stroke = FALSE,
                                   fillOpacity = .3,
                                   color = pal[i],
                                   popup = paste(sep = "<br>",
                                                 paste("<b>NDOW ID:</b> ", unique.id[i]),
                                                 paste("<b>timestamp:</b> ", df$timestamp),
                                                 paste("<b>LocID</b>: ", df$locid))
    )
    layer.group <- c(layer.group, as.character(unique.id[i]))
  } 
  device.map <- addLayersControl(device.map, overlayGroups = layer.group)
  return(device.map)
}

DeviceMapping_geojson <- function(device.map, geojson) {
  pal <- ggthemes::gdocs_pal()(20)
  for (i in seq_along(geojson)) {
    device.map <- addGeoJSON(device.map, geojson[[i]], color = pal[i],
                             weight = 1, group = names(geojson)[i])
  }
  return(device.map)
}

to_ltraj <- function(dat) {
  dat <- as.data.frame(dat)
  dat$timestamp <- as.POSIXct(dat$timestamp, format = '%Y-%m-%d %H:%M:%S')
  dat <- dat[complete.cases(dat[, c("x", "y", "timestamp")]), ] 
  # coord_conv <- SpatialPoints(cbind(as.numeric(dat$long_x),
  #                                   as.numeric(dat$lat_y)),
  #                             proj4string = CRS("+proj=longlat"))
  # coord_conv <- as.data.frame(spTransform(coord_conv, CRS("+proj=utm +zone=11")))
  # colnames(coord_conv) <- c("Easting", "Northing")
  # dat <- cbind(dat, coord_conv)
  
  traj <- as.ltraj(dat[, c("x", "y")], date = dat$timestamp, id = dat$ndowid)
  return(traj)
}

estimate_bbmm <- function(traj) {
  sig1 <- liker(traj, sig2 = 40, rangesig1 = c(1, 10), plotit = FALSE)
  bb <- kernelbb(traj, sig1[[1]]$sig1, 40, grid = 100)
  return(bb)
}

get_ud <- function(ud, percent) {
  ud_list <- list(length(percent))
  for (i in seq_along(percent)) {
    ctr <- getverticeshr(x = ud, percent = percent[i])
    ctr@proj4string <- CRS('+proj=utm +zone=11')
    ctr <- spTransform(ctr, CRS('+proj=longlat'))
    ctr <- geojson_list(ctr)
    ud_list[[i]] <- ctr
  }
  geojson <- geojson_json(Reduce(`+`, ud_list))
  return(geojson)
}

get_mud <- function(ud) {
  gjm_list <- list()
  print(paste('n elements', length(ud)))
  print('entering for loop')
  for (i in 1:length(ud)) {
    print(paste('before ud', i, 'NDOWID', names(ud)[i]))
    gj <- get_ud(ud[[i]], c(50, 70, 90))
    print(paste('before list assignment', i))
    gjm_list[[i]] <- gj
  }
  print('exit loop')
  names(gjm_list) <- names(ud)
  return(gjm_list)
}

# MOVEMENT ANALYSIS FUNCTIONS
coord_conv <- function(df, conversion = 'utm') {
  df <- df[complete.cases(df[, .(long_x, lat_y)])]
  conv <- SpatialPoints(cbind(as.numeric(df$long_x), as.numeric(df$lat_y)),
                        proj4string = CRS('+proj=longlat'))
  conv <- as.data.frame(spTransform(conv, CRS('+proj=utm +zone=11')))
  colnames(conv) <- c('x', 'y')
  df <- cbind(df, conv)
  return(df)
}

move.dist <- function(x, y) {
  dist <- c(0, sqrt((x[-1] - x[-length(x)])**2 + 
                      (y[-1] - y[-length(y)])**2))
  return(dist)
}

move.r2n <- function(x, y) {
  r2n <- (x - x[1])**2 + (y - y[1])**2
  return(r2n)
}

move.dt <- function(time) {
  if (class(time[1]) != 'POSIXct') {
    time <- fastPOSIXct(time)
  }
  dt <- c(0, unclass(time[-1]) - unclass(time[-length(time)]))
  return(dt)
}

move.speed <- function(dist, time) {
  speed <- (dist / 1000) / (time / 3600)
  return(speed)
}

movement_eda <- function(dat, plot_var, type = 'line') {
  color_pal <- ggthemes::gdocs_pal()(20)
  
  p <- ggplot(dat, aes(group = ndowid, color = factor(ndowid), fill = factor(ndowid)))
  if(type == 'histogram'){
    p <- p + geom_histogram(aes_string(x = plot_var))
  } else if (type == 'line'){
    p <- p + geom_line(aes_string(x = 'timestamp', y = plot_var), size = .75)
  } else if (type == 'point'){
    p <- p + geom_point(aes_string(x = 'timestamp', y = plot_var), size = 1.5)
  }
  p <- p + facet_wrap(~ndowid, scales = 'free', ncol = 1) +
    scale_color_manual(values = color_pal) + 
    scale_fill_manual(values = color_pal) +
    theme(panel.background = element_rect(fill = 'white'),
          plot.background = element_rect(fill = 'white'),
          panel.grid.major.x = element_line(color = 'grey90', size = .5),
          panel.grid.minor.x = element_blank(),
          panel.grid.major.y = element_line(color = 'grey90', size = .5),
          panel.grid.minor.y = element_blank(),
          legend.position = 'none',
          axis.title.x = element_blank(),
          axis.title.y = element_text(color = 'grey50', size = 14),
          axis.text.x = element_text(color = 'grey50', size = 10),
          axis.text.y = element_text(color = 'grey50', size = 10),
          axis.ticks = element_blank(),
          strip.background = element_blank(),
          strip.text = element_text(color = 'grey50', size = 12))
  return(p)
}