describe 'Morrow::Helpers.update_char_resources' do
  let(:entity) { spawn(base: 'spec:char/actor') }
  let(:char) { get_component!(entity, :character) }

  before(:all) { reset_world }

  context 'entity is not a character' do
    let(:ball) { create_entity(base: 'spec:obj/ball') }

    it 'will not raise an error' do
      expect { update_char_resources(ball) }.to_not raise_error
    end

    it 'will not add the character component' do
      update_char_resources(ball)
      expect(get_component(ball, :character)).to eq(nil)
    end
  end

  context 'health' do

    where(:base, :mod, :con_bonus, :player_health_base, :result) do
      # for npcs, base will be set, and it should not call player_health_base()
      [ [  10, 10, 1.0, nil, 10 + 10 ],
        [  10,  0, 1.0, nil, 10 ],
        [   0, 10, 1.0, nil, 10 ],
        [  10, 10, 1.2, nil, ((10 + 10) * 1.2).to_i ],
        [  10,  0, 1.2, nil, (10 * 1.2).to_i ],
        [   0, 10, 1.2, nil, (10 * 1.2).to_i ],

        # for players, base will be nil, and should call player_health_base()
        [ nil, 10, 1.0, 10, 10 + 10 ],
        [ nil,  0, 1.0, 10, 10 ],
        [ nil, 10, 1.0,  0, 10 ],
        [ nil, 10, 1.2, 10, ((10 + 10) * 1.2).to_i ],
        [ nil,  0, 1.2, 10, (10 * 1.2).to_i ],
        [ nil, 10, 1.2,  0, (10 * 1.2).to_i ],
      ]
    end

    with_them do
      before do
        # set up either health_base, or player_health_base
        if base
          char.health_base = base
          char.class_level = nil
          expect(self).to_not receive(:player_class_def_value)
              .with(entity, :health)
        else
          # for our player characters, they have a nil health_base, and must
          # have non-nil class_level
          char.health_base = nil
          char.class_level = {}
          expect(self).to receive(:player_class_def_value)
              .with(entity, :health)
              .and_return(player_health_base)
        end

        # set the health modifier
        char.health_modifier = mod

        # set the con bonus
        allow(self).to receive(:char_attr_bonus).and_return(con_bonus)

        update_char_resources(entity)
      end

      it 'will set the new max' do
        expect(char.health_max).to eq(result)
      end
    end

    context 'new health_max is higher than current health' do
      before(:each) do
        char.health_base = 100
        char.health = 200
        allow(self).to receive(:char_attr_bonus).and_return(1)
        update_char_resources(entity)
      end

      it 'will reduce current health to health_max' do
        expect(char.health).to eq(100)
      end
    end
  end
end
