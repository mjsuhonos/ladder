Ladder.controllers :resources do
  provides :json

  before do
    content_type :json
    @opts = params.symbolize_keys.slice(:all_keys, :ids, :localize)
  end

  # List all Resources (paginated)
  get :index do
    @models = Resource.all.per_page.paginate(params)

    render 'models', :format => :json
  end

  # Get an existing Resource representation
  get :index, :with => :id, :provides => [:json, :xml, :rdf] do
    @model = Resource.find(params[:id])

    halt 200, @model.to_rdfxml(url_for current_path) if :rdf == content_type or :xml == content_type

    render 'model', :format => :json
  end

  # Delete an existing Resource
  delete :index, :with => :id do
    Resource.delete(params[:id])

    body({:ok => true, :status => 200}.to_json)
  end

  # TODO: Upload a JSON hash to save as a Resource

  # List associated Files (paginated)
  get :files, :map => '/resources/:id/files' do
    @files = Resource.find(params[:id]).files.paginate(params)

    render 'files', :format => :json
  end

  # List similar Resources
  get :similar, :map => '/resources/:id/similar' do
    @similar_opts = params.symbolize_keys.slice(:amatch, :hashdiff)
    @models = Resource.find(params[:id]).similar(@similar_opts)

    render 'models', :format => :json
  end

end