# frozen_string_literal: true

module Dummy
  class Section < ::ViewComponent::Base
    def initialize(title: nil, **options)
      @title = title
      @options = options
    end

    erb_template <<-ERB
      <div class="Section">
        <% if @title %>
          <div class="Section-Title">
            <%= @title %>
          </div>
        <% end %>
        <div class="Section-Content">
          <%= content %>
        </div>
      </div>
    ERB
  end
end
