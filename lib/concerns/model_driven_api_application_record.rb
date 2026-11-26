module ModelDrivenApiApplicationRecord
    extend ActiveSupport::Concern
    
    # Fixes: https://stackoverflow.com/a/76781489
    included do
        # Every column but the API-hidden secrets (Api::HiddenSecrets, host Odoo #6313): filtering or
        # sorting on a hash would reveal it a character at a time.
        def self.ransackable_attributes(auth_object = nil)
            column_names + _ransackers.keys - Api::HiddenSecrets.for(self)
        end
    
        def self.ransackable_associations(auth_object = nil)
            reflect_on_all_associations.map { |a| a.name.to_s } + _ransackers.keys
        end
    end
end