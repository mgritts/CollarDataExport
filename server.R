library(shiny, verbose = FALSE)
library(leaflet, verbose = FALSE)
library(data.table, verbose = FALSE)
library(gridExtra, verbose = FALSE)
library(geojsonio, verbose = FALSE)
library(lubridate, verbose = FALSE)
library(ggplot2, verbose = FALSE)
library(sp, verbose = FALSE)
library(adehabitatHR, verbose = FALSE)
library(fasttime, verbose = FALSE)
source("global.R")

dat <- fread("V:/ActiveProjects/Game/BGDB/Collars.csv", encoding = "UTF-8")
dat_animal <- read.csv("V:/ActiveProjects/Game/BGDB/Animals.csv")
#dat <- fread("Collars.csv", encoding = "UTF-8")
#dat_animal <- read.csv("Animals.csv")
dat$timestamp <- dat[, fastPOSIXct(timestamp)]

dat_animal <- dat_animal[dat_animal$deviceid < 1000000, ] # THIS REMOVES ALL VHF COLLARS, WORK AROUND

shinyServer(function(input, output) {

  # PAGE 1 LOGIC
  output$animal.table <- DT::renderDataTable({
    df <- dat_animal[dat_animal$spid == input$sl_species, 
                     c(2, 1, 4, 3, 7, 8, 5)]
    if (input$sl_species == "MULD") {
      df <- df[df$mgmtarea == input$sl_mgmtarea, ]
    }
    DT::datatable(df, rownames = FALSE,
                  colnames = c("Species", "NDOW ID", "Device ID", "Area",
                               "Inservice Date", "Outservice Date", "Fate"),
              class = "cell-border stripe")
  })
  
  # PREVIEW MAP, EVERY 20 LOCATIONS
  output$preview <- renderLeaflet({ 
      CollarMap(df_subset())
    })

  # LIST OF NDOW IDS TO SUBSET DATAFRAME
  id_list <- reactive({
    return(as.numeric(strsplit(input$tx_ndowid, ', ')[[1]]))
  })
  
  # DATAFRAME SUBSET BY SELECTED SPECIES, MGMT AREA, ID, DATE
  df_subset <- reactive({
    if (is.null(input$tx_ndowid) | input$tx_ndowid == "") {
      df <- dat[species == input$sl_species, ]
      if (input$sl_species == "MULD") {
        df <- df[mgmtarea == input$sl_mgmtarea, ]
      }
    } else {
      df <- dat[species == input$sl_species &
                ndowid %in% id_list(), ]
      if (input$ck_date == TRUE) {
        df <- df[timestamp >= as.POSIXct(input$sl_dates[1]) & 
                 timestamp <= as.POSIXct(input$sl_dates[2]), ]
      }
    }
    return(df)
  })
  
  # OUTPUT INFO FOR ANIMALS SELECTED IN MAP
  output$dataInfo <- renderUI({
    HTML(
      paste(sep = "<br/>",
            paste("<b>Total Animals:</b> ", length(unique(df_subset()$ndowid))),
            paste("<b>Total Points:</b> ", nrow(df_subset())),
            paste("<b>Min. Date:</b> ", min(df_subset()$timestamp)),
            paste("<b>Max. Date:</b> ", max(df_subset()$timestamp))
            ))
      })
  
  # PAGE 1, CLEAR INPUT
  observeEvent(input$ac_reset, {
    shinyjs::reset("tx_ndowid")
    shinyjs::reset("sl_dates")
    shinyjs::reset("ck_date")
  })
  
# PAGE 2 LOGIC, SPATIAL ANALYSIS
  # CREATE DATAFRAME WITH MOVEMENT PARAMETERS
  move_df <- eventReactive(input$ac_UpdateMap, {
    df <- coord_conv(df_subset())
    df[, ':=' (dist = move.dist(x, y),
               R2n = move.r2n(x, y),
               mth = month(timestamp),
               hr = hour(timestamp),
               dt = move.dt(timestamp)), by = ndowid]
    df[, ':=' (sig.dist = cumsum(dist),
               speed = move.speed(dist, dt)), by = ndowid]
    p <- movement_eda(df, plot_var = input$y.input, type = input$fig.type)
    #return(list(df, p))
    return(df)
  })
  
  # PAGE 2 MAP, EVERY POINT
  hr_ud <- eventReactive(input$ac_UpdateMap, {
    if (input$rd_nPoints == 'Smooth') {
      hr_map <- CollarMap(df_subset())
    } else {
      hr_map <- DeviceMapping(df_subset())
    }
    
    if (input$sl_HomeRange == 'Minimum Convex Polygon') {
      cp <- SpatialPoints(move_df()[, .(x, y)], CRS('+proj=utm +zone=11'))
      cp <- mcp(cp, percent = 99)
      cp <- spTransform(cp, CRS('+proj=longlat'))
      hr <- geojson_json(cp)
    } else if (input$sl_HomeRange == 'Kernel Density') {
      kd <- move_df()
      coordinates(kd) <- kd[, .(x, y)]
      kd@proj4string <- CRS('+proj=utm +zone=11')
      kd <- kernelUD(kd[, 2], h = 'href')
      hr <- get_mud(kd)
    } else if (input$sl_HomeRange == 'Brownian Bridge') {
      bb <- to_ltraj(move_df())
      bb <- estimate_bbmm(bb)
      hr <- geojson_json(geojson_list(get_ud(bb, 90)) +
                          geojson_list(get_ud(bb, 70)) +
                          geojson_list(get_ud(bb, 50)))
    }
    hr_map <- DeviceMapping_geojson(hr_map, hr)
    return(hr_map)
  })
  
  # MAP OUTPUT
  output$map <- renderLeaflet({
    hr_ud()
  })
  
# PAGE 3, MOVEMENT ANALYSIS
  move_plots <- eventReactive(input$ac_RunAnalysis, {
    p <- movement_eda(move_df(), plot_var = input$y.input, type = input$fig.type)
    return(p)
  })
  output$move.plot <- renderPlot({
    move_plots()
  })
  
  # PAGE 4
  # ALL DATA OUTPUT BUTTON
  output$collar.table <- DT::renderDataTable({
    DT::datatable(move_df(), rownames = FALSE,
                  class = "cell-border stripe")
  })
  
  # DOWNLOAD DATA BUTTON
  output$downloadData <- downloadHandler(
    filename = function() {paste("CollarData", ".csv", sep = "")},
    content = function(file) {
      write.csv(df_subset(), file)
    }
  )
})
