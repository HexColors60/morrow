describe System::Teleport do
  include World::Helpers

  let(:leo) { 'spec:mob/leonidas' }
  let(:teleport) { get_component!(leo, :teleport) }
  let(:teleporter) { TeleporterComponent.new }
  let(:src) { create_entity(base: 'base:room') }
  let(:dest) { create_entity(base: 'base:room') }

  before(:each) do
    load_test_world
    move_entity(entity: leo, dest: src)

    teleporter.dest = dest
    add_component(src, teleporter)
  end

  def run_update
    System::Teleport.update(leo, teleport)
  end

  shared_examples 'error' do
    before(:each) { run_update }

    it 'will remove the teleport component' do
      expect(get_component(leo, :teleport)).to eq(nil)
    end

    it 'will not move the entity' do
      expect(entity_location(leo)).to eq(src)
    end
  end

  context 'with time = nil' do
    before(:each) do
      teleport.teleporter = src
      teleport.time = nil
    end

    include_examples 'error'
  end

  context 'with teleporter = nil' do
    before(:each) do
      teleport.teleporter = nil
      teleport.time = Time.now
    end

    include_examples 'error'
  end

  context 'with unknown teleporter' do
    before(:each) do
      teleport.teleporter = 'spec:invalid-id'
      teleport.time = Time.now
    end

    include_examples 'error'
  end

  context 'with teleporter without teleporter component' do
    before(:each) do
      teleport.teleporter = dest
      teleport.time = Time.now
      remove_component(dest, :teleporter)
    end

    include_examples 'error'
  end

  context 'when time is in the future' do
    before(:each) do
      teleport.teleporter = src
      teleport.time = Time.now + 1
      run_update
    end

    it 'will not move the entity' do
      expect(entity_location(leo)).to eq(src)
    end
  end

  context 'when time is in the past' do
    before(:each) do
      teleport.teleporter = src
      teleport.time = Time.now - 1
    end

    shared_examples 'move entity' do
      it 'will move the entity' do
        expect(entity_location(leo)).to eq(dest)
      end
      it 'will remove teleport component' do
        expect(get_component(leo, :teleport)).to be_nil
      end
    end

    context 'when look is false' do
      before(:each) do
        player_output(leo).clear
        teleporter.look = false
        get_component(dest, :viewable).desc = 'FAILED'
        run_update
      end

      include_examples 'move entity'

      it 'will not perform look' do
        expect(player_output(leo)).to_not include('FAILED')
      end
    end

    context 'when look is true' do
      before(:each) do
        teleporter.look = true
        player_output(leo).clear
        get_component(dest, :viewable).desc = 'PASSED'
        run_update
      end

      include_examples 'move entity'

      it 'will not perform look' do
        expect(player_output(leo)).to include('PASSED')
      end
    end

    context 'when to_entity is set' do
      before(:each) do
        teleporter.to_entity = "PASSED\n"
        player_output(leo).clear
        run_update
      end

      include_examples 'move entity'
      it 'will send to_entity string to player' do
        expect(player_output(leo)).to include('PASSED')
      end
    end
  end
end
