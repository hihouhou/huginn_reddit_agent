require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::RedditAgent do
  before(:each) do
    @valid_options = Agents::RedditAgent.new.default_options
    @checker = Agents::RedditAgent.new(:name => "RedditAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
