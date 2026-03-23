# frozen_string_literal: true

require "date"

module Railbow
  module Demo
    module Fixtures
      # Fictional pet shop SaaS — "PawShop"
      # 4 authors: Alice Chen, Bob Wilson, Carol Davis, Me (current user)
      DEMO_USER_NAME = "Me"
      DEMO_USER_EMAIL = "me@example.com"

      AUTHORS = {
        alice: {name: "Alice Chen", email: "alice@pawshop.dev"},
        bob: {name: "Bob Wilson", email: "bob@pawshop.dev"},
        carol: {name: "Carol Davis", email: "carol@pawshop.dev"},
        me: {name: DEMO_USER_NAME, email: DEMO_USER_EMAIL}
      }.freeze

      # Each entry: [days_ago, time, name, author, status, tables, branch, landed_days_after]
      # landed_days_after: if > 0, the landing date badge shows (must be >7 to trigger)
      MIGRATION_TEMPLATES = [
        # ── ~68 days ago (pre-last month) ──
        [68, "09:30:12", "CreateVeterinarians",           :alice, "up",   ["vets"],                     nil, 0],
        [66, "14:15:00", "CreatePets",                    :bob,   "up",   ["pets"],                     nil, 13],
        [65, "11:00:30", "CreateOwners",                  :alice, "up",   ["owners"],                   nil, 13],
        [62, "16:30:00", "AddBreedAndColorToPets",        :me,    "up",   ["pets"],                     nil, 0],
        [59, "08:45:00", "CreateAppointments",            :carol, "up",   ["appointments"],             nil, 0],
        [57, "15:12:00", "AddOwnerIdToPets",              :bob,   "up",   ["pets", "owners"],           nil, 12],
        [55, "10:00:00", "CreateVaccinations",            :alice, "up",   ["vaccinations"],             nil, 0],
        [53, "17:20:00", "AddPhoneToOwners",              :carol, "up",   ["owners"],                   nil, 0],
        [51, "09:15:00", "CreateTreatments",              :me,    "up",   ["treatments"],               nil, 0],
        [49, "14:00:00", "AddWeightToPets",               :bob,   "up",   ["pets"],                     nil, 0],
        # ── ~45 days ago (last month) ──
        [45, "09:30:00", "CreateBillingRecords",          :me,    "up",   ["bills"],                    nil, 0],
        [43, "16:00:00", "AddVetIdToAppointments",        :carol, "up",   ["appointments", "vets"],     nil, 0],
        [41, "12:00:00", "CreateMedicalRecords",          :bob,   "up",   ["records"],                  nil, 15],
        [39, "08:30:00", "AddIndexOnPetsBreed",           :alice, "up",   ["pets"],                     nil, 0],
        [37, "14:00:00", "CreateSpecies",                 :me,    "up",   ["species"],                  nil, 0],
        [35, "11:00:00", "AddSpeciesIdToPets",            :me,    "up",   ["pets", "species", "breeds"],nil, 0],
        [33, "09:30:00", "AddNotesToAppointments",        :carol, "up",   ["appointments"],             nil, 0],
        [31, "15:45:00", "CreateLabResults",              :alice, "up",   ["labs"],                     nil, 0],
        [29, "10:20:00", "AddDosageToTreatments",         :bob,   "up",   ["treatments"],               nil, 0],
        [27, "13:00:00", "CreateReminders",               :me,    "up",   ["reminders", "pets"],        nil, 0],
        # ── ~25 days ago (current month) ──
        [24, "10:00:00", "CreatePrescriptions",           :bob,   "up",   ["prescriptions"],            nil, 10],
        [22, "14:00:00", "AddWeightHistoryToPets",        :alice, "up",   ["pets"],                     nil, 0],
        [20, "16:30:00", "AddStatusToAppointments",       :carol, "up",   ["appointments"],             nil, 0],
        [18, "09:00:00", "CreateInventory",               :me,    "up",   ["inventory"],                nil, 0],
        [16, "11:30:00", "AddAllergiesToPets",            :alice, "up",   ["pets", "allergies"],         nil, 0],
        [14, "08:30:00", "RenameAmountOnBills",           :me,    "up",   ["bills"],                    nil, 0],
        [10, "15:00:00", "AddMicrochipToPets",            :bob,   "up",   ["pets"],                     nil, 0],
        [5,  "16:00:00", "AddInsuranceToOwners",          :carol, "up",   ["owners", "plans", "bills", "logs"], "VET-150", 0],
        [3,  "11:00:00", "CreateInsuranceClaims",         :me,    "up",   ["claims"],                   "VET-152", 0],
        [2,  "14:30:00", "AddPolicyNumberToBills",        :me,    "down", ["bills"],                    "VET-152", 0],
      ].freeze

      # Build migrations with dates relative to today.
      def self.migrations
        today = Date.today
        MIGRATION_TEMPLATES.map do |days_ago, time, name, author_key, status, tables, branch, landed_after|
          date = today - days_ago
          h, m, s = time.split(":").map(&:to_i)
          version = date.strftime("%Y%m%d") + format("%02d%02d%02d", h, m, s)

          landed_date = landed_after > 7 ? date + landed_after : nil

          author = AUTHORS[author_key]
          {
            status: status,
            version: version,
            name: name,
            author_name: author[:name],
            author_email: author[:email],
            branch: branch,
            landed_date: landed_date,
            tables: tables
          }
        end
      end

      ROUTES = [
        # Pets
        {verb: "GET", path: "/pets", reqs: "pets#index", name: "pets"},
        {verb: "GET", path: "/pets/new", reqs: "pets#new", name: "new_pet"},
        {verb: "POST", path: "/pets", reqs: "pets#create", name: ""},
        {verb: "GET", path: "/pets/:id", reqs: "pets#show", name: "pet"},
        {verb: "GET", path: "/pets/:id/edit", reqs: "pets#edit", name: "edit_pet"},
        {verb: "PATCH|PUT", path: "/pets/:id", reqs: "pets#update", name: ""},
        {verb: "DELETE", path: "/pets/:id", reqs: "pets#destroy", name: ""},
        # Owners
        {verb: "GET", path: "/owners", reqs: "owners#index", name: "owners"},
        {verb: "POST", path: "/owners", reqs: "owners#create", name: ""},
        {verb: "GET", path: "/owners/:id", reqs: "owners#show", name: "owner"},
        # Appointments (nested under pets)
        {verb: "GET", path: "/pets/:pet_id/appointments", reqs: "appointments#index", name: "pet_appointments"},
        {verb: "POST", path: "/pets/:pet_id/appointments", reqs: "appointments#create", name: ""},
        {verb: "GET", path: "/pets/:pet_id/appointments/:id", reqs: "appointments#show", name: "pet_appointment"},
        # API namespace
        {verb: "GET", path: "/api/v1/pets", reqs: "api/v1/pets#index", name: "api_v1_pets"},
        {verb: "GET", path: "/api/v1/pets/:id", reqs: "api/v1/pets#show", name: "api_v1_pet"}
      ].freeze

      # Simulate `db:migrate` running — list of [name, timing_seconds]
      MIGRATE_STEPS = [
        ["CreateInsuranceClaims", [
          ["create_table(:insurance_claims)", 0.0043],
          ["add_index(:insurance_claims, :owner_id)", 0.0012]
        ]],
        ["AddPolicyNumberToBills", [
          ["add_column(:bills, :policy_number, :string)", 0.0008]
        ]],
        ["AddInsuranceToOwners", [
          ["add_column(:owners, :insurance_provider, :string)", 0.0006],
          ["add_column(:owners, :insurance_id, :string)", 0.0005],
          ["add_index(:owners, :insurance_provider)", 0.2310]
        ]]
      ].freeze
    end
  end
end
