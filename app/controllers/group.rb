Ladder.controllers :groups do
  provides :json

  get :index do
    @groups = Group.all # TODO: implement limit
    @opts = params.symbolize_keys.slice(:all_keys, :localize)

    content_type :json
    render 'groups', :format => :json
  end

  get :index, :with => :id do
    @group = Group.find(params[:id])
    @opts = params.symbolize_keys.slice(:all_keys, :localize)

    content_type 'json'
    render 'group', :format => :json
  end

  get :index, :map => '/groups/:id/models' do
    @models = Group.find(params[:id]).models.only(:id, :md5, :version)
    @opts = {}

    content_type 'json'
    render 'models', :format => :json
  end

end