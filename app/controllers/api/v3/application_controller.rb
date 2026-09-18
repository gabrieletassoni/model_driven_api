class Api::V3::ApplicationController < Api::V2::ApplicationController
  include Pagy::Backend

  def index
    authorize! :index, @model unless custom_action?

    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    scope = apply_filters(@model.all)
    scope = apply_sorting(scope)

    pagy, records = pagy(scope, page: page_number, limit: page_size)

    serializer = Api::V3::SerializerFactory.serializer_for(@model)
    render json: serializer.new(records, **serializer_opts).serializable_hash.merge(meta: { total: pagy.count }),
           status: :ok
  end

  def show
    authorize! :show, @record unless custom_action?

    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    serializer = Api::V3::SerializerFactory.serializer_for(@model)
    render json: serializer.new(@record, **serializer_opts).serializable_hash, status: :ok
  end

  def create
    authorize! :create, @model unless custom_action?

    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    record = @model.new(jsonapi_attributes)
    record.save!
    serializer = Api::V3::SerializerFactory.serializer_for(@model)
    render json: serializer.new(record, **serializer_opts).serializable_hash, status: :created
  end

  def update
    authorize! :update, @record unless custom_action?

    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    @record.update!(jsonapi_attributes)
    serializer = Api::V3::SerializerFactory.serializer_for(@model)
    render json: serializer.new(@record, **serializer_opts).serializable_hash, status: :ok
  end

  alias_method :patch, :update

  def destroy
    authorize! :destroy, @record unless custom_action?

    status, result, status_number = check_for_custom_action
    return render json: result, status: (status_number.presence || 200) if status == true

    @record.destroy!
    head :no_content
  end

  private

  def apply_filters(scope)
    filter_params = params[:filter] || {}
    filter_params.each do |field, value|
      next unless @model.ransackable_attributes.include?(field.to_s)
      scope = scope.where(field => value)
    end
    scope
  end

  def apply_sorting(scope)
    return scope if params[:sort].blank?
    params[:sort].to_s.split(",").each do |field|
      if field.start_with?("-")
        scope = scope.order(field[1..] => :desc)
      else
        scope = scope.order(field => :asc)
      end
    end
    scope
  end

  def page_number
    (params.dig("page", "number") || 1).to_i
  end

  def page_size
    (params.dig("page", "size") || Pagy::DEFAULT[:limit] || 25).to_i
  end

  def jsonapi_attributes
    (params.dig("data", "attributes") || {}).to_h
  end

  # Hybrid sideloading: json_attrs[:include] keys are the default;
  # the client can override with ?include=assoc1,assoc2 (empty string = no sideloads).
  def requested_includes
    return default_includes if params["include"].nil?
    params["include"].to_s.split(",").filter_map { |s| s.strip.to_sym unless s.strip.empty? }
  end

  def default_includes
    jattrs = @model.respond_to?(:json_attrs) ? (@model.json_attrs || {}) : {}
    Array(jattrs[:include]).flat_map do |item|
      case item
      when Hash then item.keys
      when Symbol then [item]
      else []
      end
    end
  end

  # JSON:API sparse fieldsets: ?fields[roles]=name,lock_version
  def sparse_fields
    return {} if params["fields"].blank?
    params["fields"].to_h.transform_keys(&:to_sym).transform_values { |v| v.to_s.split(",").map(&:to_sym) }
  end

  def serializer_opts
    opts = {}
    includes = requested_includes
    opts[:include] = includes if includes.any?
    fields = sparse_fields
    opts[:fields] = fields if fields.any?
    opts
  end
end
