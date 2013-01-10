define [
  'underscore'
  'backbone'
  'chaplin/lib/utils'
  'chaplin/lib/event_broker'
], (_, Backbone, utils, EventBroker) ->
  'use strict'

  # Shortcut to access the DOM manipulation library
  $ = Backbone.$

  class Layout # This class does not extend View

    # Borrow the static extend method from Backbone
    @extend = Backbone.Model.extend

    # Mixin an EventBroker
    _(@prototype).extend EventBroker

    # The site title used in the document title.
    # This should be set in your app-specific Application class
    # and passed as an option
    title: ''

    # An hash to register events, like in Backbone.View
    # It is only meant for events that are app-wide
    # independent from any view
    events: {}

    # Register @el, @$el and @cid for delegating events
    el: document
    $el: $(document)
    cid: 'chaplin-layout'

    # Region collection; used to assign canonocial names to selectors
    regions: null

    constructor: ->
      @initialize arguments...

    initialize: (options = {}) ->
      @title = options.title
      @settings = _(options).defaults
        titleTemplate: _.template("<%= subtitle %> \u2013 <%= title %>")
        openExternalToBlank: false
        routeLinks: 'a, .go-to'
        skipRouting: '.noscript'
        # Per default, jump to the top of the page
        scrollTo: [0, 0]

      @regions = []

      @subscribeEvent 'beforeControllerDispose', @hideOldView
      @subscribeEvent 'startupController', @showNewView
      @subscribeEvent '!adjustTitle', @adjustTitle

      @subscribeEvent '!region:show', @showRegion
      @subscribeEvent '!region:register', @registerRegionHandler
      @subscribeEvent '!region:unregister', @unregisterRegionHandler

      # Set the app link routing
      if @settings.routeLinks
        @startLinkRouting()

      # Set app wide event handlers
      @delegateEvents()

    # Take (un)delegateEvents from Backbone
    # -------------------------------------
    delegateEvents: Backbone.View::delegateEvents
    undelegateEvents: Backbone.View::undelegateEvents

    # Controller startup and disposal
    # -------------------------------

    # Handler for the global beforeControllerDispose event
    hideOldView: (controller) ->
      # Reset the scroll position
      scrollTo = @settings.scrollTo
      if scrollTo
        window.scrollTo scrollTo[0], scrollTo[1]

      # Hide the current view
      view = controller.view
      view.$el.hide() if view

    # Handler for the global startupController event
    # Show the new view
    showNewView: (context) ->
      view = context.controller.view
      view.$el.show() if view

    # Handler for the global startupController event
    # Change the document title to match the new controller
    # Get the title from the title property of the current controller
    adjustTitle: (subtitle = '') ->
      title = @settings.titleTemplate {@title, subtitle}

      # Internet Explorer < 9 workaround
      setTimeout (-> document.title = title), 50

    # Automatic routing of internal links
    # -----------------------------------

    startLinkRouting: ->
      if @settings.routeLinks
        $(document).on 'click', @settings.routeLinks, @openLink

    stopLinkRouting: ->
      if @settings.routeLinks
        $(document).off 'click', @settings.routeLinks

    # Handle all clicks on A elements and try to route them internally
    openLink: (event) =>
      return if utils.modifierKeyPressed(event)

      el = event.currentTarget
      $el = $(el)
      isAnchor = el.nodeName is 'A'

      # Get the href and perform checks on it
      href = $el.attr('href') or $el.data('href') or null

      # Basic href checks
      return if href is null or href is undefined or
        # Technically an empty string is a valid relative URL
        # but it doesn’t make sense to route it.
        href is '' or
        # Exclude fragment links
        href.charAt(0) is '#'

      # Checks for A elements
      return if isAnchor and (
        # Exclude links marked as external
        $el.attr('target') is '_blank' or
        $el.attr('rel') is 'external' or
        # Exclude links to non-HTTP ressources
        el.protocol not in ['http:', 'https:', 'file:']
      )

      # Apply skipRouting option
      skipRouting = @settings.skipRouting
      type = typeof skipRouting
      return if type is 'function' and not skipRouting(href, el) or
        type is 'string' and $el.is skipRouting

      # Handle external links
      internal = not isAnchor or el.hostname in [location.hostname, '']
      unless internal
        if @settings.openExternalToBlank
          # Open external links normally in a new tab
          event.preventDefault()
          window.open el.href
        return

      if isAnchor
        path = el.pathname
        queryString = el.search.substring 1
        # Append leading slash for IE8
        path = "/#{path}" if path.charAt(0) isnt '/'
      else
        [path, queryString] = href.split '?'
        queryString ?= ''

      # Create routing options and callback
      options = {queryString}
      callback = (routed) ->
        # Prevent default handling if the URL could be routed
        if routed
          event.preventDefault()
        else unless isAnchor
          location.href = path
        return

      # Pass to the router, try to route the path internally
      @publishEvent '!router:route', path, options, callback

      return

    # Region management
    # -----------------

    # Handler for `!region:register`.
    registerRegionHandler: (params...) ->
      if arguments.length is 1
        # A single parameter is assumed to be the view instance; register all
        # regions exposed.
        @registerRegions params...

      else
        # Else we're expecting all three parameters and the intent to register
        # a single region.
        @registerRegion params...

    # Registering one region bound to a view.
    registerRegion: (instance, name, selector) ->
      # Remove the region if there was already one registered perhaps by
      # a base class.
      @unregisterRegion instance, name

      # Place this region registration into the regions array.
      @regions.unshift {instance, name, selector}

    # Triggered by view; passed in the regions hash.
    # Simply register all regions exposed by it
    registerRegions: (instance) ->
      # Regions can be be extended by subclasses, so we need to check the
      # whole prototype chain for matching regions. Regions registered by the
      # more-derived class overwrites the region registered by the less-derived
      # class.
      prototypeChain = utils.getPrototypeChain instance
      for prototype in prototypeChain.reverse()
        # Iterate over each declared region and its selector.
        for selector, name of prototype.regions
          @registerRegion instance, name, selector

    # Handler for `!region:unregister`.
    unregisterRegionHandler: (params...) ->
      if arguments.length is 1
        # A single parameter is assumed to be the view instance; unregister all
        # regions bound to the view.
        @unregisterRegions params...

      else
        # Else we're expecting both parameters and the intent to unregister
        # a single named region.
        @unregisterRegion params...

    # Unregisters a specific named region from a view.
    unregisterRegion: (instance, name) ->
      @regions = _(@regions).reject (region) ->
        region.instance.cid is instance.cid and region.name is name

    # When views are disposed; remove all their registered regions.
    unregisterRegions: (instance) ->
      @regions = _(@regions).reject (region) ->
        region.instance.cid is instance.cid

    # When views are instantiated and request for a region assignment;
    # attempt to fulfill it.
    showRegion: (name, instance) ->
      # Find an appropriate region
      region = _.find @regions, (region) ->
        region.name is name and not region.instance.stale

      # Assert that we got a valid region
      if _.isUndefined region
        throw new Error "No region registered under #{name}"

      # Apply the region selector
      instance.container = region.instance.$el.find(region.selector)

    # Disposal
    # --------

    disposed: false

    dispose: ->
      return if @disposed

      @regions = @regions[..]
      delete @regions

      @stopLinkRouting()
      @unsubscribeAllEvents()
      @undelegateEvents()

      delete @title

      @disposed = true

      # You’re frozen when your heart’s not open
      Object.freeze? this
