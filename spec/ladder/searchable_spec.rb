require 'spec_helper'

describe Ladder::Searchable do
  before do
    Mongoid.load!('mongoid.yml', :development)
    Mongoid.logger.level = Moped.logger.level = Logger::DEBUG
    Mongoid.purge!

    Elasticsearch::Model.client = Elasticsearch::Client.new host: 'localhost:9200', log: true
    Elasticsearch::Model.client.indices.delete index: '_all'

    LADDER_BASE_URI = 'http://example.org'

    class Thing
      include Ladder::Resource
      include Ladder::Searchable
    end

    class Person
      include Ladder::Resource
      include Ladder::Searchable
    end
  end
  
  it_behaves_like 'a Resource'
  it_behaves_like 'a Searchable'
  
  after do
    Object.send(:remove_const, "Thing") if Object
    Object.send(:remove_const, "Person") if Object
  end
end