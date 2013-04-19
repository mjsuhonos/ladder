class Tenant
  include Mongoid::Document
  include Mongoid::Timestamps

  field :api_key
  field :email
  field :database

  before_validation :generate_api_key
  before_validation :generate_database

  before_create :set_scope
  before_update :set_scope
  before_save :set_scope
  before_destroy :set_scope

  validates_presence_of :api_key
  validates_presence_of :email
  validates_presence_of :database

  store_in database: 'ladder', collection: 'tenants'

  def set_scope
    self.with(:database => :ladder)
  end

  def generate_api_key
    key = SecureRandom.hex
    self.api_key = key unless self.api_key
    key
  end

  def generate_database
    self.database = self.email.parameterize unless self.database
  end

  def to_hash
    self.serializable_hash
  end

end