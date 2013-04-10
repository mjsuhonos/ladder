Ladder.controllers :search do
  provides :json

  before do
    content_type :json
    @opts = params.symbolize_keys.slice(:all_keys, :ids, :localize)
  end

  get :index do
    halt 400, {:error => 'No query provided'}.to_json
  end

  get :index, :with => :q do
    search
  end

  get :resources, :with => :q do
    search({'filters' => { 'type' => {'type' => ['resource']}}}) # FIXME: allow symbols
  end

  get :concepts, :with => :q do
    search({'filters' => { 'type' => {'type' => ['concept']}}}) # FIXME: allow symbols
  end

  get :agents, :with => :q do
    search({'filters' => { 'type' => {'type' => ['agent']}}}) # FIXME: allow symbols
  end

end