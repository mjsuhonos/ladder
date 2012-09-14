desc "Map/Re-map Resources from MODS data"

namespace :mods do

  task :map, [:remap] => :environment do |t, args|

    args.with_defaults(:remap => false)

    resources = Resource.mods

    # only select resources which have not already been mapped
    resources = resources.where(:dcterms.exists => false, \
                                :bibo.exists => false, \
                                :prism.exists => false) \
                                unless args.remap

    exit if resources.empty?

    puts "Mapping #{resources.size(true)} Resources from MODS records with #{Parallel.processor_count} processors..."

    # break resources into chunks for multi-processing
    options = {:chunk_num => 1, :per_chunk => LadderHelper::dynamic_chunk(resources)}
    chunks = []
    while chunk = resources.page(options[:chunk_num]).per(options[:per_chunk]) \
                            and chunk.size(true) > 0
      chunks << chunk
      options[:chunk_num] += 1
    end

    # queries are executed in sequence, so traverse last-to-first
    chunks.reverse!

    # disable callbacks for indexing and tree generation on save
    Resource.reset_callbacks(:save)
    Resource.reset_callbacks(:validate)
    Resource.reset_callbacks(:validation)

    Agent.reset_callbacks(:save)
    Agent.reset_callbacks(:validate)
    Agent.reset_callbacks(:validation)

    Parallel.each(chunks) do |chunk|

      chunk.each do |resource|

        # load MODS XML document
        xml = Nokogiri::XML(resource.mods).remove_namespaces!

        # map MODS elements to embedded vocabs
        resource.vocabs = LadderMapping::MODS::vocabs(xml.xpath('/mods').first)

        # map related resources as tree hierarchy
        relations = LadderMapping::MODS::relations(xml.xpath('/mods/relatedItem'))
        resource.assign_attributes(relations[:fields])

        if relations[:parent].nil?
          # if resource does not have a parent, assign siblings as children
          children = relations[:siblings]
        else
          children = []

          relations[:parent].save
          resource.parent = relations[:parent]
          relations[:siblings].each { |sibling| resource.parent.children << sibling }
        end

        resource.children = children + relations[:children]

        # store relation types in vocab fields
        agents = LadderMapping::MODS::agents(xml.xpath('/mods/name'))
        resource.assign_attributes(agents[:fields])
        resource.agents << agents[:agents]

        # TODO
        #concepts = LadderMapping::MODS::concepts(xml.xpath('SOME_PATH'))

        resource.save
      end

      # Make sure to flush the GC when done a chunk
      GC.start
    end

  end
end