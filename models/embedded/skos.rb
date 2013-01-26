class SKOS
  include Model::Embedded
  bind_to RDF::SKOS, :type => Array, :only => [:prefLabel, :altLabel, :hiddenLabel, :broader, :narrower]
  embedded_in :concept
end