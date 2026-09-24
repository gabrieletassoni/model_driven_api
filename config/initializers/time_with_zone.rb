# REMOVED (3.11.0): this file used to monkey-patch ActiveSupport::TimeWithZone#as_json
# to always return `utc` ("Force json rendered datetimes to UTC", 2021):
#
#   class ActiveSupport::TimeWithZone
#     def as_json(options = nil) = utc
#   end
#
# Why it was removed: the patch flattened EVERY TimeWithZone to UTC at JSON time, so any
# value deliberately localized for the client — e.g. TimeZoneAware's `<field>_server_tz` /
# `<field>_record_tz` (thecore_backend_commons), also reused by mytask's Gantt endpoint —
# was rendered as the bare UTC value ("...T08:00:00.000Z" instead of
# "...T10:00:00.000+02:00"), making those attributes identical to the raw field.
#
# Why removing it is safe: the guarantee the patch provided ("API datetimes are UTC") is now
# enforced at its source instead — ModelDrivenApi::Engine refuses to boot unless
# `config.time_zone` is UTC (see the :enforce_utc_time_zone initializer in
# lib/model_driven_api/engine.rb). With Time.zone pinned to UTC, every plain datetime column
# still serializes through Rails' standard TimeWithZone#as_json as "...Z", exactly as before;
# only values explicitly converted with `in_time_zone(...)` now keep their own offset.
