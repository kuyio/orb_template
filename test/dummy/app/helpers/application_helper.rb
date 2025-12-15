# frozen_string_literal: true

module ApplicationHelper
  def on_click(action, *modifiers, **values)
    attributes = { 'on-click' => action.to_s }
    values.each do |key, value|
      attributes["on-value-#{key.to_s.dasherize}"] = value.is_a?(String) ? value : value.to_json
    end

    attributes['on-click-modifiers'] = modifiers.map(&:to_s).join(' ') if modifiers.any?

    attributes
  end
end
