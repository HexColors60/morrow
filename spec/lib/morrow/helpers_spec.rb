describe Morrow::Helpers do
  before(:each) { reset_world }
  let(:leo) { 'spec:mob/leonidas' }

  describe '.send_to_char(char: nil, buf: nil)' do
    context 'char has no ConnectionComponent' do
      it 'will not error' do
        char = create_entity
        expect { send_to_char(char: char, buf: 'blah') }
            .to_not raise_error
      end
    end
    context 'char is connected' do
      it 'will append buf to connection.buf' do
        conn = Morrow.config.components[:connection].new
        buf = conn.buf
        buf << 'pas'
        char = create_entity(components: conn)
        send_to_char(char: char, buf: "sed\n")
        expect(buf).to eq("passed\n")
      end

      it 'will append a trailing newline if one is not provided' do
        conn = Morrow.config.components[:connection].new
        buf = conn.buf
        char = create_entity(components: conn)
        send_to_char(char: char, buf: 'passed')
        expect(buf).to eq("passed\n")
      end
    end
  end

  describe '.match_keyword(buf, *pool, multiple: false)' do
    context 'multiple: false' do
    end
    context 'mutliple: true' do
    end
  end

  describe '.spawn(base:, area: nil)' do
    it 'will set Metadata.area to the area provided' do
      entity = spawn(base: [], area: :passed)
      expect(get_component(entity, :metadata).area).to eq(:passed)
    end
  end

  describe '.visible_contents(actor: nil, cont: nil)' do
    context 'when the container does not have the ContainerComponent' do
      it 'will return an empty array' do
        entity = create_entity
        expect(visible_contents(actor: leo, cont: entity)).to eq([])
      end
    end

    context 'when the container is empty' do
      it 'will return an empty Array' do
        bag = create_entity(base: 'morrow:obj/bag/small')
        expect(visible_contents(actor: leo, cont: bag)).to eq([])
      end
    end

    context 'when an item in the container is visible to the actor' do
      it 'will be in included in the results' do
        bag = create_entity(base: 'morrow:obj/bag/small')
        ball = spawn_at(dest: bag, base: 'morrow:obj/junk/ball')
        expect(visible_contents(actor: leo, cont: bag))
            .to contain_exactly(ball)
      end
    end
    context 'when an item in the container is not visible to the actor' do
      # XXX commenting out this pending test until we get visibility
      # it 'will not be included in the results'
    end
  end

  describe '.save_entities(dest, *entities)' do
    let(:player) do
      player = create_entity(base: [ 'spec:save/base', 'morrow:race/elf' ])
      remove_component(player, :spawn_point)

      # Add some non-unique components to the player
      add_component(player, affect: { field: :wolf })
      add_component(player, affect: { field: :bear })

      # Modify a non-unique component we got from the base
      # XXX need to re-add this; removed with hook component removal

      player
    end
    let(:inventory) do
      10.times.map do
        spawn_at(dest: player, base: 'morrow:obj/junk/ball')
      end
    end
    let(:entities) { [ player ] + inventory }
    let(:path) { tmppath << '.yml' }
    after(:each) { File.unlink(path) if File.exist?(path) }

    def entity_snapshot(entity)
      entity_components(entity).flatten.map do |comp|
        next unless comp and comp.save?
        { component_name(comp) => comp.to_h }
      end.compact
    end

    context 'dest does not exist' do
      it 'will create dest' do
        save_entities(path, entities)
        expect(File.exist?(path)).to be(true)
      end
    end

    context 'dest exists' do
      context 'an error occurs white writing' do
        it 'will not modify original dest file' do
          File.open(path, 'w') { |f| f.write('passed') }
          file = instance_double('File')
          allow(file).to receive(:write).and_raise('oops')
          expect(File).to receive(:open).and_yield(file)

          expect { save_entities(path, entities) }.to raise_error(RuntimeError)
          expect(File.read(path)).to eq('passed')
        end
      end
    end

    context 'written once' do
      it 'will write all entities to dest' do
        # snapshot each of the entities before we save them
        snapshot = entities.inject({}) { |o,e| o[e] = entity_snapshot(e); o }

        save_entities(path, entities)

        # Just be very sure this destroy works
        Morrow.em.destroy_entity(*entities)
        entities.each { |e| expect(entity_exists?(e)).to be(false) }

        # And load the entities back up
        yaml = File.read(path)    # for debugging
        load_entities(path)

        entities.each do |entity|
          expect(entity_snapshot(entity)).to eq(snapshot[entity])
        end
      end
    end

    context 'written twice' do
      it 'will write all entities to dest' do
        # snapshot each of the entities before we save them
        snapshot = entities.inject({}) { |o,e| o[e] = entity_snapshot(e); o }

        2.times do
          save_entities(path, entities)

          # Just be very sure this destroy works
          Morrow.em.destroy_entity(*entities)
          entities.each { |e| expect(entity_exists?(e)).to be(false) }

          # And load the entities back up
          load_entities(path)
        end

        entities.each do |entity|
          expect(entity_snapshot(entity)).to eq(snapshot[entity])
        end
      end
    end
  end

  describe '.move_entity' do
    let(:script) { Morrow::Script.new('true', freeze: false) }
    let(:dest) { create_entity(base: 'morrow:room') }
    let(:src) { create_entity(base: 'morrow:room') }

    context 'when dest has on_enter hook' do
      it 'will call on_enter script after moving entity' do
        expect(script).to receive(:call) do |args: {}, config: {}|
          here = args[:here]; entity = args[:entity]
          expect(here).to eq(dest)
          expect(entity).to eq(leo)
          expect(entity_contents(here)).to include(leo)
        end
        get_component!(dest, :container)[:on_enter] = script;
        move_entity(entity: leo, dest: dest)
      end
    end

    def boxes(field, value)
      e = create_entity
      c = get_component!(e, :corporeal)
      c[field] = value
      e
    end

    [ [ 'volume', Morrow::EntityTooLarge ],
        [ 'weight', Morrow::EntityTooHeavy ] ].each do |attr, error|
      [ [ 'unlimited', nil, 100 ],
          [ 'full', 100, 100 ],
          [ 'nearly full', 100, 99 ],
          [ 'not full', 100, 50 ] ].each do |state, max, cur|
        [ [ 'corporeal', 50 ],
            [ 'non-corporeal', nil ] ].each do |entity_type, value|

          context 'dest %s is %s, entity is %s' %
              [ attr, state, entity_type, attr, value || 'nil' ] do

            let(:entity) { create_entity(base: 'spec:char') }

            before(:each) do
              get_component!(dest, :container)['max_' + attr] = max
              move_entity(dest: dest, entity: boxes(attr, cur))
              if entity_type == 'corporeal'
                get_component!(entity, :corporeal)[attr] = value
              else
                remove_component(entity, :corporeal)
              end
            end

            if value && max && value + cur > max
              it 'will not move the entity' do
                before = entity_location(entity)
                begin
                  move_entity(entity: entity, dest: dest)
                rescue
                end
                expect(entity_location(entity)).to eq(before)
              end
              it "will raise #{error}" do
                expect { move_entity(entity: entity, dest: dest) }
                    .to raise_error(error)
              end
            else
              it 'will move the entity' do
                move_entity(entity: entity, dest: dest)
                expect(entity_location(entity)).to eq(dest)
              end
              it 'will not raise error' do
                expect { move_entity(entity: entity, dest: dest) }
                    .to_not raise_error
              end
            end
          end
        end
      end
    end

    [ { src: true,  dest: false, teleport: false },
      { src: true,  dest: true,  teleport: true },
      { src: false, dest: false, teleport: false },
      { src: false, dest: true,  teleport: true }
    ].each do |p|

      context 'src %s teleporter, dest %s teleporter' %
          [ p[:src] ? 'is' : 'is not', p[:dest] ? 'is' : 'is not' ] do

        let(:teleport) { get_component(leo, :teleport) }

        before(:each) do
          move_entity(dest: src, entity: leo)

          if p[:src]
            get_component!(src, :teleporter)
            get_component!(leo, :teleport)
          else
            remove_component(src, :teleporter)
            remove_component(leo, :teleport)
          end

          if p[:dest]
            t = get_component!(dest, :teleporter)
          else
            remove_component(dest, :teleporter)
          end

          move_entity(dest: dest, entity: leo)
        end

        if p[:teleport]
          it 'will add teleport component' do
            expect(teleport).to_not be(nil)
          end
          it 'will set the teleporter field' do
            expect(teleport.teleporter).to eq(dest)
          end
          it 'will set the time' do
            expect(teleport.time).to be > now
          end
        else
          it 'will remove any teleport component' do
            expect(get_component(leo, :teleport)).to be(nil)
          end
        end
      end
    end

    context 'teleporter has Numeric delay' do
      let(:teleport) { get_component(leo, :teleport) }
      before(:each) { get_component!(dest, :teleporter).delay = 10 }

      it 'will set time to delay seconds in the future' do
        move_entity(dest: dest, entity: leo)
        expect(teleport.time).to be_within(1).of(now + 10)
      end
    end
    context 'teleporter has Range delay' do
      let(:teleport) { get_component(leo, :teleport) }
      before(:each) { get_component!(dest, :teleporter).delay = 60..90 }

      it 'will set time to random seconds in the future' do
        move_entity(dest: dest, entity: leo)
        expect(teleport.time - now).to be_between(60, 90)
      end
    end
  end
end
