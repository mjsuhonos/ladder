class Tenant
  include Mongoid::Document

  field :email, type: String
  field :api_key, type: String
  field :database, type: String
  field :properties, type: Hash, default: {
    # FIXME: TEMPORARY FOR DEBUGGING
    models: [
      { name: 'Resource', vocabs: ['RDF::DC', 'RDF::MODS', 'RDF::BIBO'], types: ['RDF::DC.BibliographicResource', 'RDF::MODS.ModsResource', 'RDF::BIBO.Document'] },
      { name: 'Concept',  vocabs: ['RDF::SKOS', 'RDF::MADS'], types: ['RDF::SKOS.Concept', 'RDF::MADS.Concept'] },
      { name: 'Agent',    vocabs: ['RDF::FOAF', 'RDF::VCARD'], types: ['RDF::FOAF.Agent', 'RDF::VCARD.Agent'] },
    ]
  }

  after_initialize :generate_api_key
  after_initialize :set_database

  after_find :define_models
  after_create :define_models

  validates_presence_of :email, :api_key, :database

  store_in database: 'ladder'

  def generate_api_key
    # API key is a 32-character random Hex string
    self.api_key ||= SecureRandom.hex
  end

  def set_database
    address = Mail::Address.new(self.email)
    self.database ||= address.domain unless address.domain.nil?
  end
  
  # TODO: handle model removal?
  def define_models
    return unless self.properties[:models] and self.properties[:models].is_a? Array
    
    self.properties[:models].map do |model|
      Ladder::RDF.model model.merge module: "L#{self.id}"
    end
  end

end