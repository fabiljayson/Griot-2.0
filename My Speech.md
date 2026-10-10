My Speech

Thank you the President of the jury for giving me the floor, Honourable president of the jury, dear members of the jury, Guest and invitees. Welcome to our Defence.

During our 03 month internship at Shaderl we work on the theme design and implementation of a digital platform for african cultural heritage (Griot AI). And our Plan of work for today's presentation goes as Follow

1.	Introduction (Company Overview)
2.	Context and Problematic
3.	Proposed Solution
4.	Methodology and Technologies Used
5.	Demonstration
6.	Problem Encountered
7.	Conclusion

Talking about our internship site, Shaderl is a non-governmental start-up created by Mr. ASANE Derick in the year 2023, located at Monti Express Union. With main aim to empower individuals with intelligent tools helping bridging the gap between today's potential and tommorow opportunites. At Shaderl we proposed activities and services such as Training in software field and Software development.

Diving now to our context, African countries have a very rich cultural heritage, including traditional stories, legends, languages, customs, ceremonies, craft and historical sites. However, a significant part of this heritage is transmitted orally or stored in fragmented sources As a result, some cultural knowledge can gradually disappear, especially as younger generations bocomes less connected to traditional methods of transmission. Existing platforms such as websites, video platforms, digital arhcives contian valuable information but the experience is often fragmented. Users have to consult different different platforms to discover stories, artefacts, regions and cultural practices.

The presevation of Cultural heritage, is hindered by outdated methods that fail to engage younger generations and risk valuable cuntural knowledge. Bringing us to the following Question "HOW CAN WE PRESERVE AND PROMOTE CULTURAL HERITAGE THROUGH INTERACTIVE STORYTELLING, WHILE INCREASING ACCESSIBILITY FOR WIDER AUDIENCES".

Our general objective was to implement a cross-platform application (Griot Ai) that preserves and promotes Cameroonian folktales, legends and traditions through an authentic and engaging digital experience by combining text, quizzes, audio, video, artefacts, and AI generated content (story telling) which will provide a more centralized repository for fragmanted cultural information.

During the modeling of our platform we use UML and 2TUP coupled together as an Analysis method. We design several diagram such as the Use case, Having 03 actors explorer, contributor and Admin, each of them performing different action respective to their roles in the platform. We got the class diagram to represent the static view of our application, helping us to describe the attributes and operations a class is imposed in the system. Furthermore, we have the activity diagram representing the graphical workflows that showing the steps needed in the realization of a particular process.

Our physical architecture follows a client-server architecture having the client tier communicated directly with the server. Griot-AI follows a layered lgoical architecture composed of mainly a presentaiotn layer(MVVM) responsible for the user interface and interaction, an application layer(MVT) which manages manages the apps logic, auth, content and communication with external services and a data layer(Postgre/SQlite). Communication between them is through REST APIs over HTTPS.

As technology used, we choosed Flutter as Client layer because of its ease to be used on different platform within the same codebase, Django RestApi as Framework so as to facilitate our API integration and have a stong backend codebase, SQLIte as Local database for its facility to store and retreive data and lastly PostgreSQl for our Deployment Db for high security.

The platform contains many Functionalities but we will focus on the main ones like the Story telling, Audio player, Video generation and Qr_Scan.

During the entire design and implementation we encountered a major problem, Artefact integration because many Cultural instituion don't store them online but only onsite, and deploying them in the platform need a licence which we could not afford. And As perspective implementing the Virtual Reality technology for a 3D museum immersive experiment.

Nevertheless, This project successfully created a solution for preserving oral tradition and historical knowledge through multimedia content. Enabling our users to discover cultural heritage and conect to physical cultural sites with digital experiences.

Thanks you all for your Kind attention we are all open to your questions and criticism.