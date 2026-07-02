# frozen_string_literal: true

RSpec.describe "general things", :git, :nvim do
  popups = %w[
    bisect branch branch_config cherry_pick commit
    bundle clone diff dispatch fetch file_dispatch forge help ignore log merge mergetool notes
    patch pull push rebase remote remote_config repos reset revert shortlog sparse_checkout stash
    subtree submodule tag worktree run
  ]

  popups.each do |popup|
    it "can invoke #{popup} popup without status buffer", :with_remote_origin do
      nvim.keys("q")
      nvim.lua("require('anvil').open({ '#{popup}' })")
      sleep(0.1) # Allow popup to open

      expect(nvim.filetype).to eq("AnvilPopup")
      expect(nvim.errors).to be_empty
    end
  end
end
