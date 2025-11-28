# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    @title = 'Welcome to ORB'
    @message = 'Hello World, from the <code>ORB</code> template engine!'
    @show_greeting = true
    @dynamic_attributes = { id: 'foo', class: 'bar' }
  end

  def slim; end
  def erb; end
  def orb; end
  def haml; end
end
