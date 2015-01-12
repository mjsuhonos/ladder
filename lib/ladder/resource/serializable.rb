module Ladder::Resource::Serializable

  ##
  # Return JSON-LD representation
  #
  # @see ActiveTriples::Resource#dump
  def as_jsonld(opts = {})
    JSON.parse update_resource(opts.slice :related).dump(:jsonld, {standard_prefixes: true}.merge(opts))
  end

  ##
  # Generate a qname-based JSON representation
  #
  def as_qname(opts = {})
    qname_hash = type.empty? ? {} : {rdf: {type: type.first.pname }}

    resource_class.properties.each do |field_name, property|
      ns, name = property.predicate.qname
      qname_hash[ns] ||= Hash.new

      object = self.send(field_name)

      if relations.keys.include? field_name
        if opts[:related]
          qname_hash[ns][name] = object.to_a.map { |obj| obj.as_qname }
        else
          qname_hash[ns][name] = object.to_a.map { |obj| "#{obj.class.name.underscore.pluralize}:#{obj.id}" }
        end
      elsif fields.keys.include? field_name
        qname_hash[ns][name] = read_attribute(field_name)
      end
    end

    qname_hash
  end

  ##
  # Return a framed, compacted JSON-LD representation
  # by embedding related objects from the graph
  #
  # NB: Will NOT embed related objects with same @type. Spec under discussion, see https://github.com/json-ld/json-ld.org/issues/110
  def as_framed_jsonld
    # FIXME: Force autosave of related documents using Mongoid-defined methods
    # Required for explicit autosave prior to after_update index callbacks
    methods.select{|i| i[/autosave_documents/] }.each{|m| send m}
    json_hash = as_jsonld related: true

    context = json_hash['@context']
    frame = {'@context' => context, '@type' => type.first.pname}
    JSON::LD::API.compact(JSON::LD::API.frame(json_hash, frame), context)
  end
  
end