# frozen_string_literal: true

module Demo
  class Card < ::ViewComponent::Base
    renders_many :sections

    def initialize(title:, **options)
      @title = title
      @options = options
    end

    erb_template <<-ERB
      <%= tag.div(class: classes) do %>
        <div class="Card-Title"><%= @title %></div>
        <% sections.each do |section| %>
          <div class="Card-Section">
            <%= section %>
          </div>
        <% end %>
        <% if content %>
          <div class="Card-Section">
            <%= content %>
          </div>
        <% end %>
      <% end %>
    ERB

    private

    def classes
      class_names(
        @options[:class],
        "Card"
      )
    end
  end
end
