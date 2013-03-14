class FOAF
  include Model::Embedded

  bind_to RDF::FOAF, :type => Array, :localize => true

  embedded_in :agent

  track_history :on => RDF::FOAF.properties, :scope => :agent
end