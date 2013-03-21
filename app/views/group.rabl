object @group
cache @group

node do |g|
  if !! @opts[:all_keys]
    h = g.to_normalized_hash(@opts)
    h[:_id] = g.id
    h[:md5] = Digest.hexencode(g.md5.to_s)
  else
    h = {:_id => g.id, :heading => g.heading}
  end

  h
end

node @group.type.underscore.pluralize.to_sym do
  @group.models.only(:id).map(&:id)
end