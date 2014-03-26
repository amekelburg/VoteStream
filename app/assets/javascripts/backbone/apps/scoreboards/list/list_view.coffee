@App.module "ScoreboardsApp.List", (List, App, Backbone, Marionette, $, _) ->

  class List.View extends Marionette.Layout
    template: 'scoreboards/list/view'
    id: 'list'

    regions:
      filterBarRegion: '#filter-bar-region'
      resultsRegion: '#results-region'
      mapRegion: '#map-region'

    templateHelpers:
      percent: -> Math.floor(@votes * 100 / (@totalVotes || 1))
      percentFormatted: -> "#{Math.floor(@votes * 1000 / (@totalVotes || 1)) / 10.0}%"

    initialize: ->
      @si = App.request 'entities:scoreboardInfo'
      @results = @si.get 'results'

    onShow: ->
      view = new List.ResultsView
        collection: @results

      @resultsRegion.show view

      mapView = new App.ScoreboardsApp.Show.MapView
        hideControls:     true
        whiteBackground:  true
        noZoom:           true
        noPanning:        true
        infoWindow:       'simple'

      @filterBarRegion.show new App.ScoreboardsApp.FilterBar.View
        model: App.request('entities:scoreboardInfo')
      @mapRegion.show mapView