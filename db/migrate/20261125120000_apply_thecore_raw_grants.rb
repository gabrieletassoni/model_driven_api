# The first application of the thecore_raw role and its privileges (host ADR 0048 §3, Odoo #6093),
# for an installation that only runs db:migrate. From then on rails thecore:db:raw_grants re-applies
# them after every thecore:db:seed. Not superuser: a warning, and the migration still succeeds.
class ApplyThecoreRawGrants < ActiveRecord::Migration[7.2]
  def up
    RawSqlGrants.apply!(connection)
  end

  def down
    # Nothing to undo: the role and its grants only narrow what raw/sql can read.
  end
end
