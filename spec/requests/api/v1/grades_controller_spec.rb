require 'swagger_helper'
require 'rails_helper'
require 'json_web_token'

RSpec.describe Api::V1::GradesController, type: :controller do
    before(:all) do
      @roles = create_roles_hierarchy
    end
  
    let!(:ta) do
      User.create!(
        name: "ta",
        password_digest: "password",
        role_id: @roles[:ta].id,
        full_name: "name",
        email: "ta@example.com"
      )
    end

    let!(:s1) do
        User.create(
        name: "studenta",
        password_digest: "password",
        role_id: @roles[:student].id,
        full_name: "student A",
        email: "testuser@example.com"
        )
    end
    let!(:s2) do
        User.create(
        name: "studentb",
        password_digest: "password",
        role_id: @roles[:student].id,
        full_name: "student B",
        email: "testusebr@example.com"
        )
    end

    let!(:prof) do
        User.create!(
          name: "profa",
          password_digest: "password",
          role_id: @roles[:instructor].id,
          full_name: "Prof A",
          email: "testuser@example.com",
          mru_directory_path: "/home/testuser"
        )
    end

    let(:ta_token) { JsonWebToken.encode({id: ta.id}) }
    let(:student_token) { JsonWebToken.encode({id: s1.id}) }
    

    let!(:assignment) { Assignment.create!(name: 'Test Assignment',instructor_id: prof.id) }
    let!(:team) { Team.create!(id: 1,  assignment_id: assignment.id) }
    let!(:participant) { AssignmentParticipant.create!(user: s1, assignment_id: assignment.id, team: team, handle: 'handle') }
    let!(:questionnaire) { Questionnaire.create!(name: 'Review Questionnaire',max_question_score:100,min_question_score:0,instructor_id:prof.id) }
    let!(:assignment_questionnaire) { AssignmentQuestionnaire.create!(assignment: assignment, questionnaire: questionnaire) }
    # let!(:question) { Question.create!(questionnaire: questionnaire, txt: 'Question 1', type: 'Criterion', seq: 1) }
    # let!(:question) { questionnaire.items.create!(txt: 'Question 1',  seq: 1) }

    describe '#action_allowed' do
        context 'when the user is a Teaching Assistant' do
            it 'allows access to view_team to a TA' do
                request.headers['Authorization'] = "Bearer #{ta_token}"
                request.headers['Content-Type'] = 'application/json'
                get :action_allowed, params: { requested_action: 'view_team' }

                expect(response).to have_http_status(:ok)
                expect(JSON.parse(response.body)).to eq({ 'allowed' => true })
            end
        end
        
        context 'when the user is a Student' do
            it 'allows access to view_team if student is viewing their own team' do    
                allow_any_instance_of(Api::V1::GradesController).to receive(:student_viewing_own_team?).and_return(true)
                allow_any_instance_of(Api::V1::GradesController).to receive(:student_or_ta?).and_return(true)

                request.headers['Authorization'] = "Bearer #{student_token}"
                request.headers['Content-Type'] = 'application/json'
                get :action_allowed, params: { requested_action: 'view_team' }

                expect(response).to have_http_status(:ok)
                expect(JSON.parse(response.body)).to eq({ 'allowed' => true })
            end

            it 'denies access to view_team if student is not viewing their own team' do
                allow_any_instance_of(Api::V1::GradesController).to receive(:student_viewing_own_team?).and_return(false)

                request.headers['Authorization'] = "Bearer #{student_token}"
                request.headers['Content-Type'] = 'application/json'
                get :action_allowed, params: { requested_action: 'view_team' }

                expect(response).to have_http_status(:forbidden)
                expect(JSON.parse(response.body)).to eq({ 'allowed' => false })
            end

            it 'allows access to view_my_scores if student has finished self review and has proper authorizations' do
                allow_any_instance_of(Api::V1::GradesController).to receive(:self_review_finished?).and_return(true)
                allow_any_instance_of(Api::V1::GradesController).to receive(:are_needed_authorizations_present?).and_return(true)
                
                request.headers['Authorization'] = "Bearer #{student_token}"
                request.headers['Content-Type'] = 'application/json'
                get :action_allowed, params: { requested_action: 'view_my_scores' }

                expect(response).to have_http_status(:ok)
                expect(JSON.parse(response.body)).to eq({ 'allowed' => true })
            end

            it 'denies access to view_my_scores if student has not finished self review or lacks authorizations' do
                allow_any_instance_of(Api::V1::GradesController).to receive(:self_review_finished?).and_return(false)

                request.headers['Authorization'] = "Bearer #{student_token}"
                request.headers['Content-Type'] = 'application/json'
                get :action_allowed, params: { requested_action: 'view_my_scores' }

                expect(response).to have_http_status(:forbidden)
                expect(JSON.parse(response.body)).to eq({ 'allowed' => false })
            end
        end
    end

    describe '#instructor_review' do
        let!(:instructor) do
            User.create!(
            name: "profn",
            password_digest: "password",
            role_id: @roles[:instructor].id,
            full_name: "Prof n",
            email: "testussder@example.com",
            mru_directory_path: "/home/testuser"
            )
        end

        let(:instructor_token) { JsonWebToken.encode({ id: instructor.id }) }
        let!(:participant) { AssignmentParticipant.create!(user: s1, assignment_id: assignment.id, team: team, handle: 'handle') }
        let!(:participant2) { AssignmentParticipant.create!(user: s2, assignment_id: assignment.id, team: team, handle: 'handle') }

        let(:assignment_team) { Team.create!(assignment_id: assignment.id) }
        let(:reviewer) { participant }
        let(:reviewee) { participant2 }

        let!(:review_response_map) do
            ReviewResponseMap.create!(
            assignment: assignment,
            reviewer: reviewer,
            reviewee: assignment_team
            )
        end

        let!(:response) do
            Response.create!(
            response_map: review_response_map,
            additional_comment: nil,
            is_submitted: false
            )
        end

        context 'when review exists' do
            it 'redirects to response#edit page' do
            # Stubbing methods for find_participant, find_or_create_reviewer, and find_or_create_review_mapping
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_participant).with('1').and_return(participant)
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_or_create_reviewer).with(instructor.id, participant.assignment.id).and_return(participant)
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_or_create_review_mapping).with(participant.team.id, participant.id, participant.assignment.id).and_return(review_response_map)
            allow(review_response_map).to receive(:new_record?).and_return(false)
            allow(Response).to receive(:find_by).with(map_id: review_response_map.map_id).and_return(response)
            allow(controller).to receive(:redirect_to_review)

            request_params = { id: 1 }
            user_session = { user: instructor }

            request.headers['Authorization'] = "Bearer #{instructor_token}"
            request.headers['Content-Type'] = 'application/json'

            get :instructor_review, params: request_params, session: user_session

            expect(controller).to have_received(:redirect_to_review).with(review_response_map)
            end
        end

        context 'when review does not exist' do
            it 'redirects to response#new page' do
            # Stubbing methods for find_participant, find_or_create_reviewer, and find_or_create_review_mapping
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_participant).with('1').and_return(participant2)
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_or_create_reviewer).with(instructor.id, participant2.assignment.id).and_return(participant2)
            allow_any_instance_of(Api::V1::GradesController).to receive(:find_or_create_review_mapping).with(participant2.team.id, participant2.id, participant2.assignment.id).and_return(review_response_map)
            allow(review_response_map).to receive(:new_record?).and_return(true)
            allow(Response).to receive(:find_by).with(map_id: review_response_map.map_id).and_return(response)
            allow(controller).to receive(:redirect_to_review)

            request_params = { id: 1 }
            user_session = { user: instructor }

            request.headers['Authorization'] = "Bearer #{instructor_token}"
            request.headers['Content-Type'] = 'application/json'

            get :instructor_review, params: request_params, session: user_session

            expect(controller).to have_received(:redirect_to_review).with(review_response_map)
            end
        end
    end

end
