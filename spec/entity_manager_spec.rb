describe Morrow::EntityManager do
  # Create some constant test components for use in our tests
  before(:all) do
    class UniqueTestComponent < Morrow::Component;
      field :a, default: :default_a
      field :b, default: :default_b
      field :value
    end
    class NonUniqueTestComponent < Morrow::Component
      not_unique
      field :x
      field :y
    end
  end

  let(:em) do
    components = {
      unique_test: UniqueTestComponent,
      unique_too: Class.new(Morrow::Component),
      non_unique_test: NonUniqueTestComponent,
      non_unique_too: Class.new(Morrow::Component) { not_unique },
    }
    described_class.new(components: components)
  end

  # 'by component argument type'
  #
  # Shared example to enumerate out each of the different component argument
  # types we support.
  #
  # Lets:
  #   comp:           [in] Component class
  #   comp_name:      [in] Symbol name for Component class
  #   comp_instance:  [in] optional instance of Component class
  #   comp_arg:      [out] argument to be used in included examples
  #
  # Parameters:
  #   include: String, name of other shared examples block to include
  #   comp_arg_type: Array of :class, :instance, :name
  #
  shared_examples 'by component argument type' do |p|
    next_include = p.delete(:include)
    types = [p.delete(:comp_arg_type)].flatten.compact

    context 'by instance' do
      let(:comp_arg) { comp_instance }
      include_examples next_include, **p
    end if types.include?(:instance) or types.empty?

    context 'by name' do
      let(:comp_arg) { comp_name }
      include_examples next_include, **p
    end if types.include?(:name) or types.empty?
  end

  describe '#create_entity()' do
    shared_examples 'will create an entity' do
      it 'will return a String' do
        expect(id).to be_a(String)
      end
      it 'will add the entity to the entities Hash' do
        id
        expect(em.entities).to have_key(id)
      end
      it 'will not return an existing id' do
        expect(em.entities.keys).to_not include(id)
      end
    end

    context 'with no arguments' do
      let(:id) { em.create_entity }
      context 'when called the first time' do
        include_examples 'will create an entity'
      end

      context 'when called multiple times' do
        before(:each) { 5.times { em.create_entity } }
        include_examples 'will create an entity'
      end
    end

    context 'with an id provided' do
      context 'that does not exist' do
        let(:id) { em.create_entity(id: 'test:by_id') }
        include_examples 'will create an entity'
      end

      context 'that already exists' do
        it 'will raise an EntityManager::DuplicateId exception' do
          em.create_entity(id: 'test:duplicate_id')
          expect { em.create_entity(id: 'test:duplicate_id') }
              .to raise_error(described_class::DuplicateId)
        end
      end
    end

    context 'with a single base' do
      before(:each) do
        comps = []
        comps << UniqueTestComponent.new(a: :failed)
        comps << NonUniqueTestComponent.new(x: :failed)
        comps << NonUniqueTestComponent.new(y: :failed)
        em.create_entity(id: 'test:base', components: comps)
      end
      let(:id) { em.create_entity(base: 'test:base') }

      include_examples 'will create an entity'

      it 'will call EntityManager#merge_entity(id, "test:base")' do
        expect(em).to receive(:merge_entity) do |dest, base|
          expect(base).to eq('test:base')
        end
        id
      end

      it 'will clear modification flags on all components' do
        mods = em.entities[id].compact.flatten
            .map { |c| c.get_modified_fields }
        expect(mods).to all(be_empty)
      end
    end

    context 'with multiple bases' do
      before(:each) do
        comp_a = UniqueTestComponent.new(a: :failed)
        comp_b = NonUniqueTestComponent.new(x: :failed)
        em.create_entity(id: 'test:base_a', components: comp_a)
        em.create_entity(id: 'test:base_b', components: comp_b)
      end
      let(:id) { em.create_entity(base: [ 'test:base_a', 'test:base_b' ]) }

      include_examples 'will create an entity'

      it 'will call EntityManager#merge_entity() for each base in order' do
        expect(em).to receive(:merge_entity).ordered do |dest, base|
          expect(base).to eq('test:base_a')
        end
        expect(em).to receive(:merge_entity).ordered do |dest, base|
          expect(base).to eq('test:base_b')
        end
        id
      end

      it 'will clear modification flags on all components' do
        mods = em.entities[id].compact.flatten
            .map { |c| c.get_modified_fields }
        expect(mods).to all(be_empty)
      end
    end

    context 'when #merge_entity raises an error' do
      it 'will not reserve the entity id' do
        expect(em).to receive(:merge_entity).and_raise(ArgumentError)
        expect { em.create_entity(id: 'failed', base: :unknown) }
            .to raise_error(ArgumentError)
        expect(em.entities).to_not have_key('failed')
      end
    end

    context 'with a single component instance' do
      let(:id) { em.create_entity(components: :unique_test) }
      include_examples 'will create an entity'

      it 'will call EntityManager#add_component() with the component' do
        expect(em).to receive(:add_component) do |_,*components|
          expect(components).to eq([ :unique_test ])
        end
        id
      end
    end

    context 'with multiple components' do
      let(:components) { [ :non_unique_test ] * 3 }
      let(:id) { em.create_entity(components: components) }
      include_examples 'will create an entity'

      it 'will call EntityManager#add_component() with the components' do
        expect(em).to receive(:add_component) do |_,*component|
          expect(component).to eq(components)
        end
        id
      end
    end

    context 'when add_component raises an exception' do
      it 'will not reserve the entity id' do
        expect(em).to receive(:add_component).and_raise(ArgumentError)
        expect { em.create_entity(id: 'failed', components: :unknown) }
            .to raise_error(ArgumentError)
        expect(em.entities).to_not have_key('failed')
      end
    end

    context 'with base and components' do
      it 'will apply base before merging components' do
        expect(em).to receive(:merge_entity).ordered
        expect(em).to receive(:add_component).ordered
        em.create_entity(base: 'test:base', components: :wolf)
      end
    end
  end

  describe '#destroy_entity()' do
    let(:entity) { em.create_entity }
    it 'will remove the entity' do
      em.destroy_entity(entity)
      expect(em.entities).to_not have_key(entity)
    end
    it 'will call update_views' do
      expect(em).to receive(:update_views).with(entity, [])
      em.destroy_entity(entity)
    end
  end

  describe '#add_component(entity, component)' do
    let(:id) { em.create_entity }

    context 'entity does not exist' do
      it 'will raise EntityManager::UnknownId' do
        other = em.create_entity
        expect { em.merge_entity('missing', other) }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    context 'unknown component' do
      context 'instance' do
        it 'will raise an UnknownComponent error' do
          expect { em.add_component(id, Class.new(Morrow::Component).new) }
              .to raise_error(described_class::UnknownComponent)
        end
      end

      context 'name' do
        it 'will call EntityManager#add_component_type()' do
          expect { em.add_component(id, :bad_name) }
              .to raise_error(described_class::UnknownComponent)
        end
      end
    end

    # 'add component'
    #
    # Lets:
    #   entity: Entity id
    #   comp_arg: component argument
    #   result: expected return
    #
    shared_examples 'add component' do |returns: nil|
      it "it will return #{returns}" do
        expect(em.add_component(entity, comp_arg)).to(result)
      end
      it 'will add the component' do
        instance = em.add_component(entity, comp_arg)
        if comp.unique?
          expect(em.get_components(entity, comp)).to eq([instance])
        else
          expect(em.get_components(entity, comp)).to include(instance)
        end
      end

      it 'will call update_views' do
        entity  # fetch this early so we don't cause a loop while mocking
        expect(em).to receive(:update_views) do |id,comps|
          expect(id).to eq(entity)
          expect(comps).to be(em.entities[entity])
        end
        em.add_component(entity, comp_arg)
      end
    end

    context 'unique component' do
      let(:comp) { UniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :unique_test }

      context 'present' do
        let(:entity) { em.create_entity(components: comp_instance) }

        shared_examples 'merge component' do
          it 'will call Component#merge!' do
            expect(comp_instance).to receive(:merge!)
            em.add_component(entity, comp_arg)
          end
        end

        include_examples 'by component argument type',
            include: 'merge component'
      end

      context 'absent' do
        let(:result) do
          comp_arg.is_a?(Morrow::Component) ? be(comp_arg) : be_a(comp)
        end
        let(:entity) { em.create_entity }
        include_examples 'by component argument type',
            include: 'add component',
            returns: 'component instance'
      end
    end

    context 'non-unique component' do
      let(:comp) { NonUniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :non_unique_test }

      context 'absent' do
        let(:result) do
          comp_arg.is_a?(Morrow::Component) ? be(comp_arg) : be_a(comp)
        end
        let(:entity) { em.create_entity }
        include_examples 'by component argument type',
            include: 'add component',
            returns: 'component instance'
      end

      context 'multiple present' do
        let(:result) do
          comp_arg.is_a?(Morrow::Component) ? be(comp_arg) : be_a(comp)
        end
        let(:entity) { em.create_entity(components: [ comp.new, comp.new ]) }
        include_examples 'by component argument type',
            include: 'add component',
            returns: 'component instance'
      end
    end

    context 'is a Hash' do
      let(:entity) { em.create_entity }

      context 'with multiple keys' do
        it 'will raise an ArgumentError' do
          expect { em.add_component(entity, a: {}, b: {}) }
              .to raise_error(ArgumentError)
        end
      end

      context 'with a single key for an unknown component' do
        it 'will raise UnknownComponent' do
          expect { em.add_component(entity, a: {}) }
              .to raise_error(described_class::UnknownComponent)
        end
      end

      context 'with a single key for a known component' do
        it 'will pass the value to the component initializer' do
          comp = em.add_component(entity, unique_test: { a: :pass })
          expect(comp.a).to eq(:pass)
        end
      end
    end
  end

  describe '#get_component(id, comp)' do
    context 'entity does not exist' do
      it 'will raise EntityManager::UnknownId' do
        expect { em.get_component('missing', :wolf) }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    # 'get component'
    #
    # Lets:
    #   entity: entity id
    #   comp_arg: component argument
    #   result: return value of get_component(entity, comp_arg)
    shared_examples 'get component' do |returns: nil|
      it "will return #{returns}" do
        expect(em.get_component(entity, comp_arg)).to eq(result)
      end
    end

    context 'unique component' do
      let(:comp) { UniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :unique_test }

      context 'unknown' do
        let(:entity) { em.create_entity }
        let(:result) { nil }

        include_examples 'by component argument type',
            include: 'get component',
            comp_arg_type: %i{ class name },
            returns: 'nil'
      end

      context 'absent' do
        let(:entity) { em.create_entity }
        let(:result) { nil }
        include_examples 'by component argument type',
            include: 'get component',
            comp_arg_type: %i{ class name },
            returns: 'nil'
      end

      context 'present' do
        let(:entity) { em.create_entity(components: comp_instance) }
        let(:result) { comp_instance }

        include_examples 'by component argument type',
            include: 'get component',
            comp_arg_type: %i{ class name },
            returns: 'component instance'
      end
    end

    context 'non-unique component' do
      let(:comp) { NonUniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :non_unique_test }

      # 'raise error'
      #
      # Lets:
      #   entity: entity id
      #   comp_arg: component argument
      shared_examples 'raise error' do
        it 'will raise an ArgumentError' do
          expect { em.get_component(entity, comp_arg) }
              .to raise_error(ArgumentError)
        end
      end

      context 'unknown' do
        let(:entity) { em.create_entity }
        include_examples 'by component argument type',
            include: 'raise error',
            comp_arg_type: %i{ class name }
      end

      context 'absent' do
        let(:entity) { em.create_entity }
        include_examples 'by component argument type',
            include: 'raise error',
            comp_arg_type: %i{ class name }
      end

      context 'present' do
        let(:entity) { em.create_entity(components: comp_instance) }
        include_examples 'by component argument type',
            include: 'raise error',
            comp_arg_type: %i{ class name }
      end
    end
  end

  describe '#get_components(id, comp)' do
    context 'entity does not exist' do
      it 'will raise EntityManager::UnknownId' do
        expect { em.get_components('missing', :noop) }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    # 'get components'
    #
    # Lets:
    #   entity: entity id
    #   comp_arg: component argument
    #   result: return value of get_component(entity, comp_arg)
    shared_examples 'get components' do |returns: nil|
      it "will return #{returns}" do
        expect(em.get_components(entity, comp_arg)).to eq(result)
      end
    end

    context 'unique component' do
      let(:comp) { UniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :unique_test }

      context 'unknown' do
        let(:entity) { em.create_entity }
        let(:result) { [] }

        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'empty Array'
      end

      context 'absent' do
        let(:entity) { em.create_entity }
        let(:result) { [] }
        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'empty Array'
      end

      context 'present' do
        let(:entity) { em.create_entity(components: comp_instance) }
        let(:result) { [ comp_instance ] }

        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'array containing single component instance'
      end
    end

    context 'non-unique component' do
      let(:comp) { NonUniqueTestComponent }
      let(:comp_instance) { comp.new }
      let(:comp_name) { :non_unique_test }

      context 'unknown ' do
        let(:entity) { em.create_entity }
        let(:result) { [] }
        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'empty array'
      end

      context 'absent' do
        let(:entity) { em.create_entity }
        let(:result) { [] }

        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'empty array'
      end

      context 'present' do
        let(:components) { 5.times.map { comp.new } }
        let(:entity) { em.create_entity(components: components) }
        let(:result) { components }

        include_examples 'by component argument type',
            include: 'get components',
            comp_arg_type: %i{ class name },
            returns: 'array of all component instances'
      end
    end
  end

  describe '#remove_component(id, comp)' do
    context 'entity does not exist' do
      it 'will raise EntityManager::UnknownId' do
        expect { em.remove_component('missing', :comp) }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    # 'remove component'
    #
    # Lets:
    #   entity: entity id
    #   comp_arg: Component/instance/name argument to remove_component()
    #   result: expected return from remove_component()
    #   after: expected return from get_components() after removed
    #
    # Parameters:
    #   remove: human-readable description of what is removed
    #   returns: human-readable description of result
    #   update: should update_views be called
    #
    shared_examples 'remove component' do |remove: nil, returns: nil,
        update: true|
      let(:other_components) do
        em.add_component(entity, *[ :non_unique_too ] * 3)
      end
      before(:each) { other_components }

      it "will return #{returns}" do
        expect(em.remove_component(entity, comp_arg)).to eq(result)
      end
      it "will remove #{remove}" do
        em.remove_component(entity, comp_arg)
        expect(em.get_components(entity, comp)).to eq(after)
      end
      it 'will not remove other components' do
        em.remove_component(entity, comp_arg)
        expect(em.get_components(entity, :non_unique_too))
            .to eq(other_components)
      end

      if update
        it 'will call update_views' do
          entity  # fetch this early so we don't cause a loop while mocking
          expect(em).to receive(:update_views) do |id,comps|
            expect(id).to eq(entity)
            expect(comps).to be(em.entities[entity])
          end
          em.remove_component(entity, comp_arg)
        end
      else
        it 'will not call update_views' do
          expect(em).to_not receive(:update_views)
          em.remove_component(entity, comp_arg)
        end
      end
    end

    context 'unique component' do
      let(:comp) { UniqueTestComponent }
      let(:comp_name) { :unique_test }

      context 'absent' do
        let(:entity) { em.create_entity }
        let(:comp_instance) { comp.new }
        let(:result) { [] }
        let(:after) { [] }
        include_examples 'by component argument type',
            include: 'remove component',
            remove: 'nothing',
            returns: 'empty array',
            update: false
      end

      context 'present' do
        let(:entity) { em.create_entity(components: comp_instance) }
        let(:comp_instance) { comp.new }
        let(:result) { [ comp_instance ] }
        let(:after) { [] }
        include_examples 'by component argument type',
            include: 'remove component',
            remove: 'component instance',
            returns: 'array containing component instance'
      end

      context 'another instance is present' do
        let(:entity) { em.create_entity(components: comp_instance) }
        let(:comp_instance) { comp.new }
        let(:comp_arg) { comp.new }
        let(:result) { [] }
        let(:after) { [ comp_instance ] }
        include_examples 'remove component',
            remove: 'nothing',
            returns: 'empty array',
            update: false
      end
    end

    context 'non-unique component' do
      let(:comp) { NonUniqueTestComponent }
      let(:comp_name) { :non_unique_test }

      context 'absent' do
        let(:entity) { em.create_entity }
        let(:comp_instance) { comp.new }
        let(:result) { [] }
        let(:after) { [] }
        include_examples 'by component argument type',
            include: 'remove component',
            remove: 'nothing',
            returns: 'empty array',
            update: false
      end

      context 'single instance' do
        let(:entity) { em.create_entity(components: result) }
        let(:comp_instance) { comp.new }
        let(:result) { [ comp_instance ] }
        let(:after) { [] }
        include_examples 'by component argument type',
            include: 'remove component',
            remove: 'component instance',
            returns: 'array containing only component instance'
      end

      context 'multiple instances' do
        let(:components) { [ comp.new, comp.new, comp_instance ] }
        let(:entity) { em.create_entity(components: components) }
        let(:comp_instance) { comp.new }

        context 'by class' do
          let(:comp_arg) { comp }
          let(:result) { components }
          let(:after) { [] }
          include_examples 'remove component',
              remove: 'all instances of component',
              returns: 'array containing all instances of component'
        end
        context 'by name' do
          let(:comp_arg) { :non_unique_test }
          let(:result) { components }
          let(:after) { [] }
          include_examples 'remove component',
              remove: 'all instances of component',
              returns: 'array containing all instances of component'
        end

        context 'by instance' do
          let(:comp_arg) { components.first }
          let(:result) { [ comp_arg ] }
          let(:after) { components - [ comp_arg ] }
          include_examples 'remove component',
              remove: 'single instance of component',
              returns: 'array containing instance'
        end
      end
    end
  end

  describe '#merge_entity(dest, other)' do
    shared_examples 'will merge' do
      it 'will call update_views()' do
        # make sure both of these let()s are evaluated before we do anything.
        dest
        other
        expect(em).to receive(:update_views) do |entity,_|
          expect(entity).to eq(dest)
        end
        em.merge_entity(dest, other)
      end
    end

    context 'dest does not exist' do
      it 'will raise EntityManager::UnknownId' do
        other = em.create_entity
        expect { em.merge_entity('missing', other) }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    context 'other does not exist' do
      it 'will raise EntityManager::UnknownId' do
        base = em.create_entity
        expect { em.merge_entity(base, 'missing') }
            .to raise_error(Morrow::UnknownEntity)
      end
    end

    context 'when other has a unique component missing in dest' do
      let(:dest) { em.create_entity }
      let(:other) do
        em.create_entity(components: { unique_test: { value: :pass } })
      end

      include_examples 'will merge'

      it 'will add the component to dest' do
        em.merge_entity(dest, other)
        expect(em.get_component(dest, :unique_test).value).to eq(:pass)
      end

      it 'will clone the component' do
        em.merge_entity(dest, other)
        expect(em.get_component(dest, :unique_test))
            .to_not be(em.get_component(other, :unique_test))
      end
    end

    context 'when base has a unique component missing in other' do
      let(:dest) do
        em.create_entity(components: { unique_test: { value: :pass } })
      end
      let(:other) { em.create_entity }

      include_examples 'will merge'

      it 'will not remove component from dest' do
        em.merge_entity(dest, other)
        expect(em.get_component(dest, :unique_test).value).to eq(:pass)
      end
    end

    context 'regression: base has component, other has nil' do
      let(:comp_a) { :unique_test }
      let(:comp_b) { :unique_too }
      let(:dest) { em.create_entity }
      let(:other) { em.create_entity }

      # This should result in the following internal state:
      #   dest:  [ #<CompA ...>, nil ]
      #   other: [ nil, #<CompB ...> ]
      #
      # We were seeing an error in merge_entities with this state
      before(:each) do
        em.add_component(dest, comp_a)
        em.add_component(other, comp_b)
      end

      include_examples 'will merge'

      it 'will not error' do
        expect { em.merge_entity(dest, other) }.to_not raise_error
      end

      it 'will not remove base component' do
        em.merge_entity(dest, other)
        expect(em.get_component(dest, comp_a)).to_not be(nil)
      end
    end

    context 'when both have a unique component' do
      let(:dest_comp) { em.get_component(dest, :unique_test) }
      let(:other_comp) { em.get_component(dest, :unique_test) }
      let(:dest) { em.create_entity(components: :unique_test) }
      let(:other) { em.create_entity(components: :unique_test) }

      include_examples 'will merge'

      it 'will call dest_comp.merge!(other_comp)' do
        expect(dest_comp).to receive(:merge!).with(other_comp)
        em.merge_entity(dest, other)
      end
    end

    context 'when other has a non-unique component not present in dest' do
      let(:dest) { em.create_entity(id: 'dest') }
      let(:other_comp) { em.get_components(other, :non_unique_test).first }
      let(:other) { em.create_entity(id: 'other', components: :non_unique_test) }

      include_examples 'will merge'

      it 'will clone the other component and add it to dest' do
        expect(other_comp).to receive(:clone)
        em.merge_entity(dest, other)
      end
    end

    context 'when both have a non-unique component' do
      let(:dest) { em.create_entity(components: :non_unique_test) }
      let(:dest_comp) { em.get_components(dest, :non_unique_test).first }
      let(:other) { em.create_entity(components: :non_unique_test) }
      let(:other_comp) { em.get_components(other, :non_unique_test).first }

      include_examples 'will merge'

      it 'will not call dest_comp.merge!' do
        expect(dest_comp).to_not receive(:merge!)
        em.merge_entity(dest, other)
      end

      it 'will clone the other component and add it to dest' do
        expect(other_comp).to receive(:clone).and_return(:pass)
        em.merge_entity(dest, other)
      end

      it 'will not remove the original components from dest' do
        em.merge_entity(dest, other)
        expect(em.get_components(dest, :non_unique_test)).to include(dest_comp)
      end
    end
  end

  describe '#destroy_entity(entity)' do
    it 'will destroy the entity' do
      entity = em.create_entity
      em.destroy_entity(entity)
      expect(em.entities[entity]).to be(nil)
    end
  end

  describe '#get_view' do
    # 'gets a view'
    #
    # Lets:
    #   all: :all argument
    #   any: :any argument
    #   excl: :excl argument
    #
    shared_examples 'gets a view' do
      it 'will call EntityManager::View.new' do
        args = { all: all, any: any, excl: excl }.inject({}) do |o,(key, ary)|
          ary = [ ary ].flatten.compact
          o[key] = ary.map { |t| em.instance_eval { @comp_map[t] } }
          o
        end

        expect(described_class::View).to receive(:new).with(args)
        em.get_view(all: all, any: any, excl: excl)
      end
    end

    context 'new view' do
      context 'with duplicate components' do
        shared_examples 'will error' do
          it 'will raise an ArgumentError' do
            expect { em.get_view(all: all, any: any, excl: excl) }
                .to raise_error(ArgumentError)
          end
        end
        context 'in all and any' do
          let(:all) { UniqueTestComponent }
          let(:any) { UniqueTestComponent }
          let(:excl) { nil }
          include_examples 'will error'
        end
        context 'in all and excl' do
          let(:all) { UniqueTestComponent }
          let(:any) { nil }
          let(:excl) { UniqueTestComponent }
          include_examples 'will error'
        end
        context 'in any and excl' do
          let(:all) { nil }
          let(:any) { UniqueTestComponent }
          let(:excl) { UniqueTestComponent }
          include_examples 'will error'
        end
      end

      context 'no conflicting components' do
        let(:all) { :non_unique_test }
        let(:any) { :unique_test }
        let(:excl) { :non_unique_too }
        include_examples 'gets a view'
      end

      context 'when entities are already defined' do
        it 'will call view.update!() for defined entities' do
          entity = em.create_entity(components: :unique_test)
          view = em.get_view(all: :unique_test)
          expect(view.each.to_a.first[0]).to eq(entity)
        end
      end
    end

    context 'existing view' do
      context 'with same ordered arguments' do
        it 'will return the existing view' do
          view = em.get_view(all: [:unique_test, :non_unique_test])
          expect(em.get_view(all: [:unique_test, :non_unique_test]))
              .to be(view)
        end
      end
      context 'with different ordered arguments' do
        # This is important because when a System creates a view, its update
        # method expects the arguments to be in a specific order.
        it 'will return a different view' do
          view = em.get_view(all: [:unique_test, :non_unique_test])
          expect(em.get_view(all: [:non_unique_test, :unique_test]))
              .to_not be(view)
        end
      end
    end
  end

  describe '#update_view(entity, components)' do
    it 'will queue the update to the view' do
      view = em.get_view(all: UniqueTestComponent)
      expect(view).to_not receive(:update!)
      em.send(:update_views, :entity, :components)
    end
  end

  describe '#flush_updates()' do
    let(:views) do
      [ em.get_view(all: UniqueTestComponent),
        em.get_view(any: UniqueTestComponent),
        em.get_view(excl: UniqueTestComponent) ]
    end

    it 'will call EntityManager::View#update! any views' do
      entity = em.create_entity
      views.each do |view|
        expect(view).to receive(:update!).with(entity, :passed)
      end
      em.send(:update_views, entity, :passed)
      em.flush_updates
    end
  end
end
