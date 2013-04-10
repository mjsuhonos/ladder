Ladder.controllers :agents do
  provides :json

  before do
    content_type :json
    @opts = params.symbolize_keys.slice(:all_keys, :ids, :localize)
  end

  # List all Agents (paginated)
  get :index do
    @models = Agent.all.per_page.paginate(params)

    render 'models', :format => :json
  end

  # Get an existing Agent representation
  get :index, :with => :id, :provides => [:json, :xml, :rdf] do
    @model = Agent.find(params[:id])

    halt 200, @model.to_rdfxml(url_for current_path) if :rdf == content_type or :xml == content_type

    render 'model', :format => :json
  end

  # Delete an existing Agent
  delete :index, :with => :id do
    Agent.delete(params[:id])

    body({:ok => true, :status => 200}.to_json)
  end

  # TODO: Upload a JSON hash to save as an Agent

  # List associated Files (paginated)
  get :files, :map => '/agents/:id/files' do
    @files = Agent.find(params[:id]).files.paginate(params)

    render 'files', :format => :json
  end

  # List similar Agents
  get :similar, :map => '/agents/:id/similar' do
    @similar_opts = params.symbolize_keys.slice(:amatch, :hashdiff)
    @models = Agent.find(params[:id]).similar(@similar_opts)

    render 'models', :format => :json
  end

end