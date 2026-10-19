class Admin::InfluencerPostsController < Admin::BaseController
  def index
    @q = InfluencerPost.ransack(params[:q])
    @influencer_posts = @q.result
                           .includes(:influencer)
                           .order(posted_at: :desc, id: :desc)
                           .page(params[:page])
    @influencers = Influencer.order(:username)
  end
end
