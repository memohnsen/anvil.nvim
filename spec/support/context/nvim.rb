# frozen_string_literal: true

RSpec.shared_context "with nvim", :nvim do
  let(:nvim_mode) { :pipe }
  let(:nvim) { NeovimClient.new(nvim_mode) }
  let(:anvil_config) { "{}" }

  before { nvim.setup(anvil_config) }
  after { nvim.teardown }
end
