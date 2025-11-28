# frozen_string_literal: true

Rails.application.routes.draw do
  root to: 'home#index'

  get '/tests/errors', to: 'tests#orb_error_spot'
end
