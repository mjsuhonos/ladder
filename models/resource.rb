class DublinCore
  include LadderModel::Embedded
  bind_to RDF::DC, :type => Array
  bind_to LadderVocab::DCVocab, :type => Array
  embedded_in :resource
end

class Bibo
  include LadderModel::Embedded
  bind_to LadderVocab::Bibo, :type => Array
  embedded_in :resource
end

class Prism
  include LadderModel::Embedded
  bind_to LadderVocab::Prism, :type => Array
  embedded_in :resource
end

class Resource
  include LadderModel::Core

  # imported data objects
  field :marc, :type => CompressedBinary
  field :mods, :type => CompressedBinary

  def self.marc
    only(:marc).where(:marc.exists => true)
  end

  def self.mods
    only(:mods).where(:mods.exists => true)
  end

  # embedded RDF vocabularies
  embeds_one :dcterms, class_name: "DublinCore"
  embeds_one :bibo,    class_name: "Bibo"
  embeds_one :prism,   class_name: "Prism"

  # index embedded documents
  mapping indexes :dcterms, :type => 'object'
  mapping indexes :bibo,    :type => 'object'
  mapping indexes :prism,   :type => 'object'

  # model relations
  has_and_belongs_to_many :agents
  has_and_belongs_to_many :concepts
end