describe EntityManager::View do
  def create_view(all: [], any: [], excl: [])
    all  = [ all ]  unless all.is_a?(Array)
    any  = [ any ]  unless any.is_a?(Array)
    excl = [ excl ] unless excl.is_a?(Array)
    params = {
      all:  all.map { |c| em.send(:add_component_type, c) },
      any:  any.map { |c| em.send(:add_component_type, c) },
      excl: excl.map { |c| em.send(:add_component_type, c) }
    }
    EntityManager::View.new(**params)
  end

  let(:req_a) { Class.new(Component) }
  let(:req_b) { Class.new(Component) }
  let(:optional) { Class.new(Component) }
  let(:excluded) { Class.new(Component) }
  let(:non_uniq) { Class.new(Component) { not_unique } }
  let(:em) { EntityManager.new }
  let(:entity) { em.create_entity }
  let(:view) do
    create_view(all: [req_a, req_b], any: optional, excl: excluded)
  end

  describe '#update!(entity)' do
    shared_examples 'entity absent' do
      it 'will not add the entity to the view' do
        view.update!(entity, em.entities[entity])
        expect(view.each.map(&:first)).to_not include(entity)
      end
    end

    shared_examples 'entity present' do
      it 'will add the entity to the view' do
        view.update!(entity, em.entities[entity])
        expect(view.each.map(&:first)).to include(entity)
      end
    end

    shared_examples 'excluded components' do |present|
      context 'with an excluded Component' do
        before(:each) { em.add_component(entity, excluded) }
        include_examples 'entity absent'
      end

      context 'without any excluded Components' do
        if present
          include_examples 'entity present'
        else
          include_examples 'entity absent'
        end
      end
    end

    shared_examples 'optional components' do |present|
      context 'with an optional Components' do
        before(:each) { em.add_component(entity, optional) }
        include_examples 'excluded components', present && true
      end
      context 'without any optional Components' do
        include_examples 'excluded components', false
      end
    end

    shared_examples 'required components' do
      context 'with no required Components' do
        include_examples 'optional components', false
      end
      context 'with some required Components' do
        before(:each) { em.add_component(entity, req_a) }
        include_examples 'optional components', false
      end
      context 'with all required Components' do
        before(:each) { em.add_component(entity, req_a, req_b) }
        include_examples 'optional components', true
      end
    end

    context 'Entity is not present in view' do
      include_examples 'required components'
    end

    context 'Entity is already present in view' do
      before(:each) do
        em.add_component(entity, req_a, req_b, optional)
        view.update!(entity, em.entities[entity])
        em.remove_component(entity, req_a)
        em.remove_component(entity, req_b)
        em.remove_component(entity, optional)
      end
      include_examples 'required components'
    end

    context 'when one required Component is unique, and one is non-unique' do
      let(:view) { create_view(all: [ req_a, non_uniq]) }

      context 'and two non-unique instances exist on the Entity' do
        before(:each) { em.add_component(entity, non_uniq.new, non_uniq.new) }
        include_examples 'entity absent'
      end

      context 'and one unique, and multiple non-unique instances exist' do
        let(:non_uniqs) { 2.times.map { non_uniq.new } }
        before(:each) do
          em.add_component(entity, req_a, *non_uniqs)
          view.update!(entity, em.entities[entity])
        end
        it 'will include all non-unique instances in the record' do
          expect(view.each.first[-1]).to contain_exactly(*non_uniqs)
        end
      end
    end
    context 'when an optional Component is non-unique' do
      let(:view) { create_view(any: [ optional, non_uniq ]) }

      context 'and no non-unique instances are provided' do
        before(:each) do
          em.add_component(entity, optional)
          view.update!(entity, em.entities[entity])
        end
        it 'will add an empty array for that component in the record' do
          id, opt, non_uniq = view.each.first
          expect(non_uniq).to eq([])
        end
      end
      context 'and multiple non-unique instances are provided' do
        let(:non_uniqs) { 2.times.map { non_uniq.new } }
        before(:each) do
          em.add_component(entity, req_a, *non_uniqs)
          view.update!(entity, em.entities[entity])
        end
        it 'will include each of the non-unique instances in the record' do
          id, opt, non_uniq = view.each.first
          expect(non_uniq).to contain_exactly(*non_uniqs)
        end
      end

      context 'and multiple Entity instances have the Component' do
        let(:non_uniq_a) { non_uniq.new }
        let(:non_uniq_b) { non_uniq.new }
        let(:entity_a) { em.create_entity(components: non_uniq_a) }
        let(:entity_b) { em.create_entity(components: non_uniq_b) }
        before(:each) do
          view.update!(entity_a, em.entities[entity_a])
          view.update!(entity_b, em.entities[entity_b])
        end

        it 'will include only the Components in that Entity in the record' do
          id, opt, non_uniq = view.each.find { |id,*_| id == entity_b }
          expect(non_uniq).to contain_exactly(non_uniq_b)
        end
      end
    end
  end

  describe '#each' do
    context 'with excluded Components' do
      let(:view) { create_view(excl: [ ContainerComponent ]) }
      before(:each) { view.update!(entity, em.entities[entity]) }

      it 'will not yield a value for excluded components' do
        args = view.each.find { |id,*_| id == entity }
        expect(args.size).to be(1)
      end
    end
  end
end
