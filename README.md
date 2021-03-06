![Ladder logo](https://github.com/ladder/ladder/blob/master/logo.png)

[![Gem Version](https://badge.fury.io/rb/ladder.svg)](https://rubygems.org/gems/ladder)
[![Inline docs](http://inch-ci.org/github/ladder/ladder.svg)](http://inch-ci.org/github/ladder/ladder)
[![Build Status](https://travis-ci.org/ladder/ladder.svg)](https://travis-ci.org/ladder/ladder)

# Ladder

Ladder is a dynamic framework for [Linked Data](http://en.wikipedia.org/wiki/Linked_data) modelling, persistence, and full-text indexing. It is implemented as a series of Ruby modules that can be used individually and incorporated within existing ActiveModel frameworks (eg. [Project Hydra](http://projecthydra.org)), or combined as a comprehensive stack.

Although conceptually similar to [Spira](https://github.com/ruby-rdf/spira), Ladder takes the opposite approach: instead of making RDF repositories (triple stores) behave like ActiveModel, it allows ActiveModel objects to behave like RDF resources.

### Components

- [Mongoid](http://mongoid.org) for persistence
- [ActiveTriples](https://github.com/no-reply/ActiveTriples) for RDF handling
- [ElasticSearch](http://www.elasticsearch.org) for full-text indexing
- [ActiveJob](https://github.com/rails/rails/tree/master/activejob) for background job execution

## History

Ladder was loosely conceived over the course of several years prior to 2011 as a way to encourage the [GLAM](http://en.wikipedia.org/wiki/GLAM_(industry_sector)) community to think less dogmatically about established (often monolithic and/or niche) tools and instead embrace a broader vision of adopting more widely-used technologies.

In early 2012, Ladder began existence as an opportunity to escape from a decade of LAMP development and become familiar with Ruby.  From 2012 to late 2013, a closed prototype was built under the auspices of [Deliberate Data](http://deliberatedata.com) as a proof-of-concept to test the feasibility of the design.  For those interested in the historical code, the original [prototype](https://github.com/ladder/ladder/tree/prototype) branch is available, as is an [experimental](https://github.com/ladder/ladder/tree/l2) branch.

## Installation

Add `gem "ladder"` to your Gemfile and run `bundle`.

Or install manually with `gem install ladder`.

## Usage

* [Resources](#resources)
  * [Relations](#relations)
  * [Dynamic Resources](#dynamic-resources)
* [Files](#files)
* [Indexing](#indexing)
  * [Indexing Resources](#indexing-resources)
  * [Indexing Files](#indexing-files)
  * [Background Indexing](#background-indexing)
* [Configuration](#configuration)

### Resources

Ladder::Resources implement all the functionality of a Mongoid::Document and an ActiveTriples::Resource.  To add Ladder integration for your model, require and include the main module in your class:

```ruby
require 'ladder'

class Person
  include Ladder::Resource

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name
  property :description, predicate: RDF::DC.description
end

steve = Person.new(first_name: 'Steve', description: 'Funny-looking')
=> #<Person _id: 542f0c124169720ea0000000, first_name: {"en"=>"Steve"}, description: {"en"=>"Funny-looking"}>

steve.as_document
=> {"_id"=>BSON::ObjectId('542f0c124169720ea0000000'),
 "first_name"=>{"en"=>"Steve"},
 "description"=>{"en"=>"Funny-looking"}}

steve.as_jsonld
 # => {
 #    "@context": {
 #        "dc": "http://purl.org/dc/terms/",
 #        "foaf": "http://xmlns.com/foaf/0.1/"
 #    },
 #    "@id": "http://example.org/people/542f0c124169720ea0000000",
 #    "@type": "foaf:Person",
 #    "dc:description": {
 #        "@language": "en",
 #        "@value": "Funny-looking"
 #   },
 #   "foaf:name": {
 #        "@language": "en",
 #        "@value": "Steve"
 #   }
 # }
```

The `#property` method takes care of setting both Mongoid fields and ActiveTriples properties.  Properties with a supplied `class_name:` will create a many-to-many relation.

By default, URIs are dynamically generated based on the name of the model class and the configured base URI.  However, you can still set the base URI for a class explicitly just as you would in ActiveTriples, eg:

```ruby
Person.base_uri
=> #<RDF::URI:0x3fecf69da274 URI:http://example.org/people>

Person.configure base_uri: 'http://some.other.uri/'
=> "http://some.other.uri/"
```

See the [configuration](#configuration) section for more information on configuring default behaviour.

#### Relations

```ruby
class Person
  include Ladder::Resource

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name
  property :books, predicate: RDF::FOAF.made, class_name: 'Book'
end

class Book
  include Ladder::Resource

  configure type: RDF::DC.BibliographicResource

  property :title, predicate: RDF::DC.title
  property :people, predicate: RDF::DC.creator, class_name: 'Person'
end

b = Book.new(title: 'Heart of Darkness')
=> #<Book _id: 542f28d44169721941000000, title: {"en"=>"Heart of Darkness"}, person_ids: nil>

b.people << Person.new(first_name: 'Joseph Conrad')
=> [#<Person _id: 542f28dd4169721941010000, first_name: {"en"=>"Joseph Conrad"}, book_ids: [BSON::ObjectId('542f28d44169721941000000')]>]

b.as_jsonld
 # => {
 #    "@context": {
 #        "dc": "http://purl.org/dc/terms/"
 #    },
 #    "@id": "http://example.org/books/542f28d44169721941000000",
 #    "@type": "dc:BibliographicResource",
 #    "dc:creator": {
 #        "@id": "http://example.org/people/542f28dd4169721941010000"
 #    },
 #    "dc:title": {
 #        "@language": "en",
 #        "@value": "Heart of Darkness"
 #    }
 # }
```

You'll notice that only the RDF node for the Book object on which `#as_jsonld` was called is serialized.  To include the entire graph for related nodes, use the `related: true` option:

```ruby
b.as_jsonld related: true
 # => {
 #    "@context": {
 #        "dc": "http://purl.org/dc/terms/",
 #        "foaf": "http://xmlns.com/foaf/0.1/"
 #    },
 #    "@graph": [
 #        {
 #            "@id": "http://example.org/books/542f28d44169721941000000",
 #            "@type": "dc:BibliographicResource",
 #            "dc:creator": {
 #                "@id": "http://example.org/people/542f28dd4169721941010000"
 #            },
 #            "dc:title": {
 #                "@language": "en",
 #                "@value": "Heart of Darkness"
 #            }
 #        },
 #        {
 #            "@id": "http://example.org/people/542f28dd4169721941010000",
 #            "@type": "foaf:Person",
 #            "foaf:made": {
 #                "@id": "http://example.org/books/542f28d44169721941000000"
 #            },
 #            "foaf:name": {
 #                "@language": "en",
 #                "@value": "Joseph Conrad"
 #            }
 #        }
 #    ]
 # }
```

If you want more control over how relations are defined (eg. in the case of embedded or 1:n relations), you can just use regular Mongoid and ActiveTriples syntax:

```ruby
class Person
  include Ladder::Resource

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name

  embeds_one :address, class_name: 'Place'
  property :address, predicate: RDF::FOAF.based_near
end

class Place
  include Ladder::Resource

  configure type: RDF::VCARD.Address

  property :city, predicate: RDF::VCARD.locality
  property :country, predicate: RDF::VCARD.send('country-name')

  embedded_in :resident, class_name: 'Person', inverse_of: :address
  property :resident, predicate: RDF::VCARD.agent
end

steve = Person.new(first_name: 'Steve')
=> #<Person _id: 542f341e41697219a2000000, first_name: {"en"=>"Steve"}, address: nil>

steve.address = Place.new(city: 'Toronto', country: 'Canada')
=> #<Place _id: 542f342741697219a2010000, city: {"en"=>"Toronto"}, country: {"en"=>"Canada"}, resident: nil>

steve.as_jsonld
 # => {
 #    "@context": {
 #        "foaf": "http://xmlns.com/foaf/0.1/",
 #        "vcard": "http://www.w3.org/2006/vcard/ns#"
 #    },
 #    "@graph": [
 #        {
 #            "@id": "http://example.org/places/542f342741697219a2010000",
 #            "@type": "vcard:Address",
 #            "vcard:agent": {
 #                "@id": "http://example.org/people/542f341e41697219a2000000"
 #            },
 #            "vcard:country-name": {
 #                "@language": "en",
 #                "@value": "Canada"
 #            },
 #            "vcard:locality": {
 #                "@language": "en",
 #                "@value": "Toronto"
 #            }
 #        },
 #        {
 #            "@id": "http://example.org/people/542f341e41697219a2000000",
 #            "@type": "foaf:Person",
 #            "foaf:based_near": {
 #                "@id": "http://example.org/places/542f342741697219a2010000"
 #            },
 #            "foaf:name": {
 #                "@language": "en",
 #                "@value": "Steve"
 #            }
 #        }
 #    ]
 # }
```

Note in this case that both objects are included in the RDF graph, thanks to embedded relations. This can be useful to avoid additional queries to the database for objects that are tightly coupled.

#### Dynamic Resources

In line with ActiveTriples' [Open Model](https://github.com/ActiveTriples/ActiveTriples#open-model) design, you can define properties on any Resource instance similarly to how you would on the class:

```ruby
class Person
  include Ladder::Resource::Dynamic

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name
end

steve = Person.new(first_name: 'Steve')
=> #<Person _id: 546669234169720397000000, first_name: {"en"=>"Steve"}>

steve.description
=> NoMethodError: undefined method 'description' for #<Person:0x007fb54eb1d0b8>

steve.property :description, predicate: RDF::DC.description
=> {:description=>"http://purl.org/dc/terms/description"}

steve.description = 'Funny-looking'
=> "Funny-looking"

steve.as_document
=> {"_id"=>BSON::ObjectId('546669234169720397000000'),
 "first_name"=>{"en"=>"Steve"},
 "_context"=>{:description=>"http://purl.org/dc/terms/description"},
 "description"=>"Funny-looking"}

steve.as_jsonld
 # => {
 #    "@context": {
 #        "dc": "http://purl.org/dc/terms/",
 #        "foaf": "http://xmlns.com/foaf/0.1/"
 #    },
 #    "@id": "http://example.org/people/546669234169720397000000",
 #    "@type": "foaf:Person",
 #    "dc:description": "Funny-looking",
 #    "foaf:name": {
 #        "@language": "en",
 #        "@value": "Steve"
 #  }
```

Additionally, you can push RDF statements into a Resource instance like you would with ActiveTriples or RDF::Graph, noting that the subject is ignored since it is implicit:

```ruby
steve << RDF::Statement(nil, RDF::DC.description, 'Tall, dark, and handsome')
steve << RDF::Statement(nil, RDF::FOAF.depiction, RDF::URI('http://some.image/pic.jpg'))
steve << RDF::Statement(nil, RDF::FOAF.age, 32)

steve.as_document
=> {"_id"=>BSON::ObjectId('546669234169720397000000'),
 "first_name"=>{"en"=>"Steve"},
 "_context"=>
  {:description=>"http://purl.org/dc/terms/description",
   :depiction=>"http://xmlns.com/foaf/0.1/depiction",
   :age=>"http://xmlns.com/foaf/0.1/age"},
 "description"=>"Tall, dark, and handsome",
 "depiction"=>"http://some.image/pic.jpg",
 "age"=>32}

steve.as_jsonld
 # => {
 #    "@context": {
 #        "dc": "http://purl.org/dc/terms/",
 #        "foaf": "http://xmlns.com/foaf/0.1/",
 #        "xsd": "http://www.w3.org/2001/XMLSchema#"
 #    },
 #    "@id": "http://example.org/people/546669234169720397000000",
 #    "@type": "foaf:Person",
 #    "dc:description": "Tall, dark, and handsome",
 #    "foaf:age": {
 #        "@type": "xsd:integer",
 #        "@value": "32"
 #    },
 #    "foaf:depiction": {
 #        "@id": "http://some.image/pic.jpg"
 #    },
 #    "foaf:name": {
 #        "@language": "en",
 #        "@value": "Steve"
 #    }
 #	}
```

Dynamic properties **can not** be localized.  They can be any kind of literal, but they **can not** be a related object. They can, however, contain the related object's URI.

### Files

Files are bytestreams that store binary content using MongoDB's GridFS storage system.  They are still identifiable by a URI, and contain technical metadata about the File's contents.

```ruby
class Person
  include Ladder::Resource

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name
  property :thumbnails, predicate: RDF::FOAF.depiction, class_name: 'Image', inverse_of: nil
end

class Image
  include Ladder::File
end
```

Because Files must be the target of a one-way relation, the `inverse_of: nil` option is required on the property  (unless the `one_sided_relations` [configuration](#configuration) option is set). Note that Files **can not** be embedded.

```ruby
steve = Person.new(first_name: 'Steve')
=> #<Person _id: 549d83c64169720b32010000, first_name: {"en"=>"Steve"}>

thumb = Image.new(file: open('http://some.image/pic.jpg'))
=> #<Image _id: 549d83c24169720b32000000>

steve.thumbnails << thumb
=> [#<Image _id: 549d83c24169720b32000000, >]

steve.as_jsonld
 # => {
 #     "@context": {
 #         "foaf": "http://xmlns.com/foaf/0.1/"
 #     },
 #     "@id": "http://example.org/people/549d83c64169720b32010000",
 #     "@type": "foaf:Person",
 #     "foaf:depiction": {
 #         "@id": "http://example.org/images/549d83c24169720b32000000"
 #     },
 #     "foaf:name": {
 #         "@language": "en",
 #         "@value": "Steve"
 #     }
 # }

steve.save
 # ... File is stored to GridFS ...
=> true
```

Files have all the attributes of a GridFS file, and the stored binary content is accessed using `#data`.

```ruby
thumb.reload
=> #<Image _id: 549d86184169720b6a000000, >

thumb.as_document
=> {"_id"=>BSON::ObjectId('549d86184169720b6a000000'),
 "length"=>59709,
 "chunkSize"=>4194304,
 "uploadDate"=>2014-12-26 16:00:29 UTC,
 "md5"=>"0d4a486e2cd71c51b7a92cfe96f29324",
 "contentType"=>"image/jpeg",
 "filename"=>"549d86184169720b6a000000/open-uri20141226-2922-u66ap6"}

thumb.length
=> 59709

thumb.data
=> # ... binary data ...
```

### Indexing

#### Indexing Resources

You can index Resources for keyword searching by mixing in the Ladder::Searchable module:

```ruby
class Person
  include Ladder::Resource
  include Ladder::Searchable

  configure type: RDF::FOAF.Person

  property :first_name, predicate: RDF::FOAF.name
  property :description, predicate: RDF::DC.description
end

kimchy = Person.new(first_name: 'Shay', description: 'Real genius')
=> #<Person _id: 543b457b41697231c5000000, first_name: {"en"=>"Shay"}, description: {"en"=>"Real genius"}>

kimchy.save
=> true

results = Person.search 'shay'
 # => #<Elasticsearch::Model::Response::Response:0x007fa2ca82a9f0
 # @klass=[PROXY] Person,
 # @search=
 # #<Elasticsearch::Model::Searching::SearchRequest:0x007fa2ca830a58
 #  @definition={:index=>"people", :type=>"person", :q=>"Shay"},
 #  @klass=[PROXY] Person,
 #  @params={}>>

results.count
=> 1

results.first._source
=> {"description"=>"Real genius", "first_name"=>"Shay"}

results.records.first == kimchy
=> true
```

When indexing, you can control how your model is stored in the index by calling `#index_for_search` and supplying a block that returns a serializable hash:

```ruby
Person.index_for_search { as_jsonld }
=> :as_indexed_json

kimchy.as_indexed_json
 # => {
 #   "@context": {
 #       "dc": "http://purl.org/dc/terms/",
 #       "foaf": "http://xmlns.com/foaf/0.1/"
 #   },
 #   "@id": "http://example.org/people/543b457b41697231c5000000",
 #   "@type": "foaf:Person",
 #   "dc:description": {
 #       "@language": "en",
 #       "@value": "Real genius"
 #   },
 #   "foaf:name": {
 #       "@language": "en",
 #       "@value": "Shay"
 #   }
 # }

Person.index_for_search { as_qname }
=> :as_indexed_json

kimchy.as_indexed_json
 # => {
 #   "dc": {
 #       "description": { "en": "Real genius" }
 #   },
 #   "foaf": {
 #       "name": { "en": "Shay" }
 #   },
 #   "rdf": {
 #       "type": "foaf:Person"
 #   }
 # }
```

You can also index related objects as framed JSON-LD using `#as_framed_jsonld` or by using the `related: true` option with `#as_qname` or `#as_jsonld`.  Related objects can be serialized by default using the `:with_relations` [configuration](#configuration) option.

#### Indexing Files

Files that contain textual content (eg. HTML, PDF, ePub, DOC, etc) can be indexed when they are stored, again by mixing in the Ladder::Searchable module.  This can be useful if you want to retrieve a File by searching for the textual content that it contains.  Note that this requires the [Mapper Attachments Plugin for Elasticsearch](https://github.com/elasticsearch/elasticsearch-mapper-attachments) to be installed.

```ruby
class OCR
  include Ladder::File
  include Ladder::Searchable
end

pdf = OCR.new(file: open('http://some.location/ocr.pdf'))
=> #<OCR _id: 54add77a4169721c23000000>

pdf.save
=> true

results = OCR.search 'Moomintroll'
 # => #<Elasticsearch::Model::Response::Response:0x007fa2ca82a9f0
 # @klass=[PROXY] OCR,
 # @search=
 # #<Elasticsearch::Model::Searching::SearchRequest:0x007fa2ca830a58
 #  @definition={:index=>"ocrs", :type=>"ocr", :q=>"Moomintroll"},
 #  @klass=[PROXY] OCR,
 #  @params={}>>

results.count
=> 1

results.records.first == pdf
=> true

results.records.first.as_document
=> {"_id"=>BSON::ObjectId('54add77a4169721c23000000'),
 "length"=>12941,
 "chunkSize"=>4194304,
 "uploadDate"=>2015-01-08 01:03:54 UTC,
 "md5"=>"831a47b953d6e11d17cee7de9abd73c4",
 "contentType"=>"application/pdf",
 "filename"=>"54add77a4169721c23000000/ocr.pdf"}

results.records.first.data
=> # ... binary data ...
```

Note the use of `#records` to access the Ladder::File instances directly ([see here for more information](https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-model#search-results-as-database-records)).  However, if you want to get information about the file characteristics (including the extracted textual content), you can use a modified search query:

```ruby
results = OCR.search 'Moomintroll', fields: '*'
 # => #<Elasticsearch::Model::Response::Response:0x007fc36cadaa20
 # @klass=[PROXY] OCR,
 # @search=
 # #<Elasticsearch::Model::Searching::SearchRequest:0x007fc36cadab10
 #  @definition={:index=>"ocrs", :type=>"ocr", :body=>{:query=>{:query_string=>{:query=>"Moomintroll"}}, :fields=>"*"}},
 #  @klass=[PROXY] OCR,
 #  @params={}>>

results.count
=> 1

results.first.fields
=> {
 "file.content_type"=>["application/pdf"],
 "file.keywords"=>[""],
 "file"=>
  ["\nAnd so Moomintroll was helplessly thrown out into a strange and dangerous world and \ndropped up to his ears in the first snowdrift of his experience. It felt unpleasantly prickly \nto his velvet skin, but at the same time his nose caught a new smell. It was a more \nserious smell than any he had met before, and slightly frightening. But it made him wide \nawake and greatly interested.\n\n\n"],
 "file.date"=>["2014-12-19T15:32:58Z"],
 "file.title"=>["Untitled"]}
```

In this case, the `#fields` Hash contains all of the technical metadata obtained by Elasticsearch during indexing. Note that this is **not the same** as the metadata stored by GridFS (with the possible exception of content type). Finally, we can also provide contextual highlighting for search results by using a slightly more complex search query:

```ruby
results = OCR.search query: { query_string: { query: 'his' } }, highlight: { fields: { file: {} } }
 # => #<Elasticsearch::Model::Response::Response:0x007fd653dc8b48
 # @klass=[PROXY] OCR,
 # @search=
 # #<Elasticsearch::Model::Searching::SearchRequest:0x007fd653dc8b48
 #  @definition={:index=>"ocrs", :type=>"ocr", :body=>{:query=>{:query_string=>"Moomintroll"},
 #  :highlight=>{:fields=>{:file=>{}}}}},
 #  @klass=[PROXY] OCR,
 #  @params={}>>

results.count
=> 1

results.first.highlight.file.count
=> 2

results.first.highlight.file
=> [" <em>his</em> ears in the first snowdrift of <em>his</em> experience. It felt unpleasantly prickly \nto <em>his</em> velvet skin",
    ", but at the same time <em>his</em> nose caught a new smell. It was a more \nserious smell than any he had met"]
```

More information about highlighting queries is available in the [Elasticsearch documentation](http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/search-request-highlighting.html).

#### Background Indexing

In large-scale production environments, sending an HTTP request to Elasticsearch during the database transaction isn't optimal (especially for large Files), so Ladder uses ActiveJob to queue and process indexing operations in the background.  Just use the Ladder::Searchable::Background module in your model:

```ruby
class OCR
  include Ladder::File
  include Ladder::Searchable::Background
end

 # ...

class Person
  include Ladder::Resource
  include Ladder::Searchable::Background

  configure type: RDF::FOAF.Person
end

 # ...
```

You'll also have to set the queue adapter in your application, depending on which backend you're using:

```ruby
ActiveJob::Base.queue_adapter = :sidekiq
```

For more information on available queueing adapters and their features, see the [ActiveJob documentation](http://api.rubyonrails.org/classes/ActiveJob/QueueAdapters.html).

### Configuration

Configuration options are set using `Ladder::Config#settings`, eg:

```ruby
Ladder::Config.settings[:base_uri] = 'http://example.org'
=> "http://example.org"

Ladder::Config.settings
=> {:base_uri=>"http://example.org", :localize_fields=>false, :one_sided_relations=>false}
```

Ladder currently supports the following configuration options (defaults in parentheses):

* `:base_uri ('urn:x-ladder')`: Tells Ladder the base (root) URI to use for generating model URIs.  For a Rack-based linked data application, this will typically be the HTTP(S) URL, eg. "http://some.domain/my_application/"
* `:localize_fields (false)`: When set to `true`, Ladder will set fields defined using `#property` to be localized by default.
* `:one_sided_relations (false)`: When set to `true`, Ladder will set relations defined using `#property` to be [one-sided many-to-many](http://mongoid.org/en/mongoid/docs/relations.html#has_and_belongs_to_many) relations. Otherwise, it will define has-and-belongs-to-many (HABTM) relations.
* `:with_relations`: When set to `true`, Ladder will always include directly related objects when serializing JSON-LD.

## Contributing

Anyone and everyone is welcome to contribute.  Go crazy.

1. Fork it ( https://github.com/ladder/ladder/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Authors

MJ Suhonos / mj@suhonos.ca

## Acknowledgements

My biggest thanks to all the wonderful people who have shown interest and support for Ladder over the years.

Many thanks to Christopher Knight [@NomadicKnight](https://twitter.com/Nomadic_Knight) for ceding the "ladder" gem name.  Check out his startup, [Adventure Local](http://advlo.com) / [@advlo_](https://twitter.com/Advlo_).

## License

Apache License Version 2.0
http://apache.org/licenses/LICENSE-2.0.txt
