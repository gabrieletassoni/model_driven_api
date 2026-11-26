# Serialization options sent by the client (a / json_attrs) follow the conventions of
# Api::V2::RequestJsonAttrs (host Odoo #6285); options built by the code are untouched.
# Prepended to the module (Ruby >= 3.0 reaches the classes that already include it): records and
# the ActiveModel objects a custom action returns.
ActiveModel::Serialization.prepend(Api::V2::RequestJsonAttrs::Serialization)
