require "rails_helper"

# A model's write_only_attributes (LdapServer#admin_password, thecore_auth_commons >= 3.8.0) are
# never among the attributes v3's JSON:API serializers read, whatever json_attrs says (host Odoo #6084).
RSpec.describe Api::ResourceAttributeSet do
  it "leaves out the write-only attributes from the default and from an explicit only" do
    expect(described_class.for(LdapServer).attributes).to include(:host)
    expect(described_class.for(LdapServer).attributes).not_to include(:admin_password)
    expect(described_class.for(LdapServer, jattrs: {only: [:host, :admin_password]}).attributes).to eq([:host])
  end

  it "v3 serializes an LdapServer without its admin password" do
    server = LdapServer.create!(host: "ldap.example.com", base_dn: "dc=example,dc=com", admin_password: "Ldap-S3cret")
    json = Api::V3::SerializerFactory.serializer_for(LdapServer).new(server).serializable_hash.to_json

    expect(json).to include("ldap.example.com")
    expect(json).not_to include("Ldap-S3cret")
  end
end
